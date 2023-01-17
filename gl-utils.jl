function glGenOne(glGenFn)
    id = GLuint[0]
    glGenFn(1, id)
    glCheckError("generating a buffer, array, or texture")
    return id[]
end
glGenBuffer() = glGenOne(glGenBuffers)
glGenVertexArray() = glGenOne(glGenVertexArrays)
glGenTexture() = glGenOne(glGenTextures)
function getInfoLog(obj::GLuint)
    # Return the info log for obj, whether it be a shader or a program.
    isShader = glIsShader(obj)
    getiv = isShader == GL_TRUE ? glGetShaderiv : glGetProgramiv
    getInfo = isShader == GL_TRUE ? glGetShaderInfoLog : glGetProgramInfoLog
    # Get the maximum possible length for the descriptive error message
    len = GLint[0]
    getiv(obj, GL_INFO_LOG_LENGTH, len)
    maxlength = len[]
    # TODO: Create a macro that turns the following into the above:
    # maxlength = @glPointer getiv(obj, GL_INFO_LOG_LENGTH, GLint)
    # Return the text of the message if there is any
    if maxlength > 0
        buffer = zeros(GLchar, maxlength)
        sizei = GLsizei[0]
        getInfo(obj, maxlength, sizei, buffer)
        len = sizei[]
        unsafe_string(pointer(buffer), len)
    else
        ""
    end
end
function validateShader(shader)
    success = GLint[0]
    glGetShaderiv(shader, GL_COMPILE_STATUS, success)
    return success[] == GL_TRUE
end
function glErrorMessage()
    # Return a string representing the current OpenGL error flag, or the empty string if there's no error.
    err = glGetError()
    return err == GL_NO_ERROR ? "" :
           err == GL_INVALID_ENUM ?
           "GL_INVALID_ENUM: An unacceptable value is specified for an enumerated argument. The offending command is ignored and has no other side effect than to set the error flag." :
           err == GL_INVALID_VALUE ?
           "GL_INVALID_VALUE: A numeric argument is out of range. The offending command is ignored and has no other side effect than to set the error flag." :
           err == GL_INVALID_OPERATION ?
           "GL_INVALID_OPERATION: The specified operation is not allowed in the current state. The offending command is ignored and has no other side effect than to set the error flag." :
           err == GL_INVALID_FRAMEBUFFER_OPERATION ?
           "GL_INVALID_FRAMEBUFFER_OPERATION: The framebuffer object is not complete. The offending command is ignored and has no other side effect than to set the error flag." :
           err == GL_OUT_OF_MEMORY ?
           "GL_OUT_OF_MEMORY: There is not enough memory left to execute the command. The state of the GL is undefined, except for the state of the error flags, after this error is recorded." :
           "Unknown OpenGL error with error code $err."
end
function glCheckError(actionName="")
    message = glErrorMessage()
    if length(message) > 0
        if length(actionName) > 0
            error("Error ", actionName, ": ", message)
        else
            error("Error: ", message)
        end
    end
end

function createShader(source, typ)
    # Create the shader
    shader = glCreateShader(typ)::GLuint
    if shader == 0
        error("Error creating shader: ", glErrorMessage())
    end
    # Compile the shader
    glShaderSource(shader, 1, convert(Ptr{UInt8}, pointer([convert(Ptr{GLchar}, pointer(source))])), C_NULL)
    glCompileShader(shader)
    # Check for errors
    !validateShader(shader) && error("Shader creation error: ", getInfoLog(shader))
    return shader
end

function createShaderProgram(vertexShader, fragmentShader, geometry=nothing)
    # Create, link then return a shader program for the given shaders.
    # Create the shader program
    prog = glCreateProgram()
    if prog == 0
        error("Error creating shader program: ", glErrorMessage())
    end
    # Attach the vertex shader
    glAttachShader(prog, vertexShader)
    glCheckError("attaching vertex shader")
    # Attach the fragment shader
    glAttachShader(prog, fragmentShader)
    glCheckError("attaching fragment shader")
    if !isnothing(geometry)
        glAttachShader(prog, geometry)
        glCheckError("attaching geometry shader")
    end
    # Finally, link the program and check for errors.
    glLinkProgram(prog)
    status = GLint[0]
    glGetProgramiv(prog, GL_LINK_STATUS, status)
    if status[] == GL_FALSE
        glDeleteProgram(prog)
        error("Error linking shader: ", glGetInfoLog(prog))
    end
    return prog
end

struct GLBuffer{T}
    id::GLuint
    length::Int
    buffertype::GLenum
    usage::GLenum
    function GLBuffer(data::Vector{T}, buffertype::GLenum, usage::GLenum) where {T}
        id = glGenBuffer()
        glBindBuffer(buffertype, id)
        # size of 0 can segfault it seems
        GC.@preserve data begin
            ptr = pointer(data)
            glBufferData(buffertype, sizeof(data), ptr, usage)
        end
        glBindBuffer(buffertype, 0)
        return new{T}(id, length(data), buffertype, usage)
    end
end

Base.eltype(::GLBuffer{T}) where T = T

get_attribute_location(program::GLuint, name) = get_attribute_location(program, ascii(name))
get_attribute_location(program::GLuint, name::Symbol) = get_attribute_location(program, string(name))
function get_attribute_location(program::GLuint, name::String)
    location::GLint = glGetAttribLocation(program, name)
    if location == -1
        # warn(
        #     "Named attribute (:$(name)) is not an active attribute in the specified program object or\n
        #     the name starts with the reserved prefix gl_\n"
        # )
    elseif location == GL_INVALID_OPERATION
        error("program is not a value generated by OpenGL or\n
              program is not a program object or\n
              program has not been successfully linked")
    end
    return location
end

julia2glenum(::Type{<: Point{N, T}}) where {N, T} = julia2glenum(T)
julia2glenum(::Type{GLubyte})  = GL_UNSIGNED_BYTE
julia2glenum(::Type{GLbyte})   = GL_BYTE
julia2glenum(::Type{GLuint})   = GL_UNSIGNED_INT
julia2glenum(::Type{GLushort}) = GL_UNSIGNED_SHORT
julia2glenum(::Type{GLshort})  = GL_SHORT
julia2glenum(::Type{GLint})    = GL_INT
julia2glenum(::Type{GLfloat})  = GL_FLOAT
julia2glenum(::Type{GLdouble}) = GL_DOUBLE
julia2glenum(::Type{Float16})  = GL_HALF_FLOAT

cardinality(x) = length(x)
cardinality(x::Number) = 1
cardinality(x::Type{T}) where {T<:Number} = 1
cardinality(x::Type{<:NTuple{N}}) where {N} = N
cardinality(x::Type{<:Point{N}}) where {N} = N
cardinality(::GLBuffer{T}) where {T} = cardinality(T)


function GLVertexArray(bufferdict::Dict, indexbuffer, program)
    # get the size of the first array, to assert later, that all have the same size
    id = glGenVertexArray()
    glBindVertexArray(id)
    glBindBuffer(indexbuffer.buffertype, indexbuffer.id)
    for (name, buffer) in bufferdict
        glBindBuffer(buffer.buffertype, buffer.id)
        attribute = string(name)
        attribLocation = get_attribute_location(program, attribute)
        if attribLocation == -1
            error("Did not find attribute location in program")
        end
        glEnableVertexAttribArray(attribLocation)
        glVertexAttribPointer(attribLocation, cardinality(buffer), julia2glenum(eltype(buffer)), GL_FALSE, 0, C_NULL)
    end
    glBindVertexArray(0)
    return id
end

function GLBuffer(data; buffertype=GL_ARRAY_BUFFER, usage=GL_STATIC_DRAW)
    return GLBuffer(data, buffertype, usage)
end

function IndexBuffer(data::Vector{Cuint})
    return GLBuffer(data; buffertype=GL_ELEMENT_ARRAY_BUFFER, usage=GL_STATIC_DRAW)
end


function gluniform(location::Integer, x::Mat4f)
    xref = [x]
    glUniformMatrix4fv(location, 1, GL_FALSE, xref)
    return
end

function gluniform(location::Integer, x::Vec4f)
    xref = [x]
    glUniform4fv(GLint(location), 1, xref)
    return
end
function gluniform(location::Integer, x::Vec2f)
    xref = [x]
    glUniform2fv(GLint(location), 1, xref)
    return
end

gluniform(location::Integer, x::GLfloat) = glUniform1f(GLint(location),  x)
gluniform(location::Integer, x::Union{GLbyte, GLshort, GLint, Bool}) = glUniform1i(GLint(location),  x)


get_uniform_location(program::GLuint, name::Symbol) = get_uniform_location(program, String(name))
function get_uniform_location(program::GLuint, name::String)
    location = glGetUniformLocation(program, name)
    if location == -1
        error(
            """Named uniform (:$(name)) is not an active attribute in the specified program object or
            the name starts with the reserved prefix gl_"""
        )
    elseif location == GL_INVALID_OPERATION
        error("""program is not a value generated by OpenGL or
            program is not a program object or
            program has not been successfully linked"""
        )
    end
    location
end
