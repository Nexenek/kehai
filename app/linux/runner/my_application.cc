#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // Whether the top-level window actually got an RGBA visual applied below
  // — true only on a compositing screen. This is what the
  // `app.kehai/window#setTransparent` handler reports back to
  // DesktopWindowService.setMiniTransparency, so a non-compositing desktop
  // (a bare X11 server, notably WSLg's default) cleanly reports "no" rather
  // than painting a solid black card.
  gboolean transparency_capable;

  // Kept so transparency_method_call_cb can flip the FlView's background
  // colour at runtime, well after activate() has returned.
  FlView* flutter_view;

  // Owns the `app.kehai/window` channel for the app's lifetime.
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Handles `app.kehai/window#setTransparent` — the mini partner card asking
// for (or releasing) genuine per-pixel transparency. Mirrors
// windows/runner/transparency_channel.cpp's contract: always responds
// (never leaves Dart hanging), and the bool it succeeds with is the real
// answer, not an assumption — false whenever this screen never got an RGBA
// visual, regardless of what was asked for.
static void transparency_method_call_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(GError) error = nullptr;

  if (g_strcmp0(fl_method_call_get_name(method_call), "setTransparent") !=
      0) {
    if (!fl_method_call_respond_not_implemented(method_call, &error)) {
      g_warning("Failed to respond to %s: %s",
               fl_method_call_get_name(method_call), error->message);
    }
    return;
  }

  FlValue* args = fl_method_call_get_args(method_call);
  gboolean want_transparent = args != nullptr &&
                             fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                             fl_value_get_bool(args);
  gboolean applied = want_transparent && self->transparency_capable;

  if (self->flutter_view != nullptr) {
    GdkRGBA color;
    // Real alpha only when we're both asked for it and actually capable —
    // otherwise back to the same opaque black the view starts with, which
    // the app's own UI paints over completely.
    gdk_rgba_parse(&color, applied ? "#00000000" : "#000000");
    fl_view_set_background_color(self->flutter_view, &color);
  }

  g_autoptr(FlValue) result = fl_value_new_bool(applied);
  if (!fl_method_call_respond_success(method_call, result, &error)) {
    g_warning("Failed to respond to app.kehai/window#setTransparent: %s",
             error->message);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  GdkScreen* screen = gtk_window_get_screen(window);

  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif

  // Mini partner card transparency (kb/platform-desktop.md): only worth
  // attempting on a compositing screen. Wayland compositors and composited
  // X11 (the GNOME/KDE/etc default) support an RGBA visual; a bare X11
  // server — notably WSLg's default — does not, and asking for one there
  // just paints solid black once the background colour below goes
  // transparent. Guarded here rather than assumed, so
  // transparency_method_call_cb has a real answer to give back.
  self->transparency_capable = FALSE;
  if (screen != nullptr && gdk_screen_is_composited(screen)) {
    GdkVisual* rgba_visual = gdk_screen_get_rgba_visual(screen);
    if (rgba_visual != nullptr) {
      gtk_widget_set_visual(GTK_WIDGET(window), rgba_visual);
      gtk_widget_set_app_paintable(GTK_WIDGET(window), TRUE);
      self->transparency_capable = TRUE;
    }
  }
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Kehai");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Kehai");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent. Left opaque at startup regardless of
  // transparency_capable: the window opens in expanded mode
  // (window_mode.dart), and app.kehai/window#setTransparent is what flips
  // this once the mini card actually needs it.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  self->flutter_view = view;
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) window_codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "app.kehai/window", FL_METHOD_CODEC(window_codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, transparency_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
  self->flutter_view = nullptr;
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
