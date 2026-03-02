#version 330

in vec2 fragTexCoord;
in vec4 fragColor;


// Output fragment color
out vec4 finalColor;


void main()
{       
    vec2 vecToCenter = vec2(0.5,0.5) - fragTexCoord;
    float distToCenter = sqrt((vecToCenter.x*vecToCenter.x) + (vecToCenter.y*vecToCenter.y));
    if(distToCenter > 0.5){
        discard;
    }
    finalColor = vec4(1-distToCenter, 0,0,1);
}