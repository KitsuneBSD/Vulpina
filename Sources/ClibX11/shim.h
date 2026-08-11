#pragma once
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/Xresource.h>

// Wrappers for X11 macros that Swift cannot import directly.

/// Destroys an XImage, freeing image->data if non-NULL.
static inline int vulpina_XDestroyImage(XImage *img) {
    return XDestroyImage(img);
}

/// Clears image->data before destruction so the caller can manage the buffer.
static inline void vulpina_ximage_clear_data(XImage *img) {
    img->data = NULL;
}
