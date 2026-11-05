shader_type spatial;
// Heads: like the body, but faces never fall into self-shadow, so
// expressions stay readable under hat brims and roofs.
render_mode cull_back, depth_draw_opaque, shadows_disabled;

#include "res://shaders/character_common.gdshaderinc"
