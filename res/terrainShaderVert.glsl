#version 330 core

in vec3 vertexPosition;
in vec2 texcoords;

out vec2 uv;

uniform mat4 matModel;
uniform mat4 matView;
uniform mat4 matProjection;

void main()
{
    vec3 correctedVert = vertexPosition;
    correctedVert.y = correctedVert.z;
    correctedVert.z = 0;

    vec3 fragPosition = vec3(matModel * vec4(correctedVert, 1.0));

    gl_Position = matProjection * matView * vec4(fragPosition, 1.0);

    uv = texcoords.yx;
}
