#version 330

in vec2 vertex;
in float lastlen;
in float valid_vertex;

uniform mat4 projection, view, model;
uniform float depth_shift;

out float g_lastlen;
out int g_valid_vertex;

void main()
{
    g_lastlen = lastlen;
    int index = gl_VertexID;
    g_valid_vertex = int(valid_vertex);
    gl_Position = projection*view*model*vec4(vertex, 0, 1);
    gl_Position.z += gl_Position.w * depth_shift;
}
