#version 330

// Input vertex attributes
in vec3 vertexPosition;
in vec2 vertexTexCoord;


in mat4 instanceTransform;

// Input uniform values
uniform mat4 mvp;

out vec2 fragTexCoord;


void main()
{
    fragTexCoord = vertexTexCoord;
    float cos90 = 0;
    float sin90 = 1;
    mat4 rotation = mat4(1,0,0,0, 0,cos90,-sin90,0, 0,sin90,cos90,0, 0,0,0,1);

    gl_Position = mvp*instanceTransform*rotation*vec4(vertexPosition, 1.0);
}