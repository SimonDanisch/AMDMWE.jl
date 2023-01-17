using GLFW, ModernGL, GeometryBasics, LinearAlgebra

include("gl-utils.jl")

window = GLFW.Window()

polltask = @async begin
    while !GLFW.WindowShouldClose(window)
        GLFW.PollEvents()
        yield()
    end
end

cd(@__DIR__)
vshader = createShader(read("lines.vert", String), GL_VERTEX_SHADER)
gshader = createShader(read("lines.geom", String), GL_GEOMETRY_SHADER)
fshader = createShader(read("lines.frag", String), GL_FRAGMENT_SHADER)

program = createShaderProgram(vshader, fshader, gshader)

position = Point2f.(-2:0.2:2, -2:0.2:2)
valid_vertex = map(p -> Float32(all(isfinite, p)), position)
len0 = length(position) - 1
indices = Cuint[0; 0:len0; len0]
vertex = GLBuffer(position)
valid_vertex =  GLBuffer(valid_vertex)
indexbuffer = IndexBuffer(indices)
vbo = GLVertexArray(Dict(
    "vertex" => vertex,
    "valid_vertex" => valid_vertex
), indexbuffer, program)

cardinality(indexbuffer)
cardinality(vertex)
cardinality(valid_vertex)

uniforms = Dict(
    "thickness" => 2.0f0,
    "depth_shift" => 0.0f0,
    "projection" => Mat4f(I),
    "view" => Mat4f(I),
    "model" => Mat4f(I),
    "resolution" => Vec2f(800, 800)
)

locations = Dict(map(collect(uniforms)) do (name, type)
    return name => get_uniform_location(program, name)
end)

function render(program, vbo, uniforms, locations, index_length)
    glUseProgram(program)
    glBindVertexArray(vbo)
    for (name, location) in locations
        gluniform(location, uniforms[name])
    end
    glDrawElements(
        GL_LINE_STRIP_ADJACENCY,
        index_length,
        GL_UNSIGNED_INT, C_NULL)
    return
end

function render_frame(window)
    glViewport(0, 0, 800, 800)
    # Pulse the background blue
    glClearColor(1, 1, 1, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    # Draw our triangle
    render(program, vbo, uniforms, locations, length(indices))
    # Swap front and back buffers
    GLFW.SwapBuffers(window)
    # Poll for and process events
    GLFW.PollEvents()
end

render_frame(window)

# GLFW.DestroyWindow(window) # use to close
