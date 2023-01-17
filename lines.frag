#version 330

layout(location=0) out vec4 fragment_color;

uniform vec4 color;

void main(){
    fragment_color = vec4(0,0,0,1);
}
