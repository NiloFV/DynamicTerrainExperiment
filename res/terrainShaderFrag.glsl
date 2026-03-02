#version 330

out vec4 finalColor;

in vec2 uv;

uniform sampler2D mainTex;
uniform sampler2D maskTex;

void main() 
{
    vec4 maskSample = texture(maskTex, uv);
    vec4 texSample = texture(mainTex, uv);
    if(texSample.r < 0.5){
        discard;
    }
    
    float s = smoothstep(0.5, 0.6, texSample.r);
    vec4 col = mix(vec4(0.529, 0.467, 0.361, 1), vec4(0.42, 0.349, 0.227,1), s);
    col = mix(col, vec4(0.165, 0.263, 0.278,1), maskSample.r);
    
    finalColor = col;    
}
