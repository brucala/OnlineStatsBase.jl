#-----------------------------------------------------------------------# Aliases
const ScalarOb = Union{Number, AbstractString, Symbol}
const VectorOb = Union{AbstractVector, Tuple}
const Rows = ObsDim.First
const Cols = ObsDim.Last
const Data = Union{ScalarOb, VectorOb, AbstractMatrix}


#-----------------------------------------------------------------------# Series
struct Series{I, T <: Tuple, W <: Weight}
    weight::W
    stats::T
end
# These act as inner constructors
Series(wt::Weight, t::Tuple) = Series{input_ndims(t), typeof(t), typeof(wt)}(wt, t)

# empty
Series(o::OnlineStat...) = Series(default_weight(o), o)
Series(wt::Weight, o::OnlineStat...) = Series(wt, o)

# Init with data
Series(y::Data, wt::Weight, o::OnlineStat...) = (s = Series(wt, o); fit!(s, y))
Series(y::Data, o::OnlineStat...) = (s = Series(o...); fit!(s, y))

#-----------------------------------------------------------------------# Series Methods
stats(s::Series) = s.stats
value(s::Series) = value.(stats(s))

#---------------------------------------------------------------------------# fit helpers
struct DataIterator{D <: ObsDimension, T}
    data::T
    dim::D
end
Base.start(o::DataIterator) = 1
Base.done(o::DataIterator, i) = i > length(o)

# Matrix
Base.next(o::DataIterator{Rows}, i) = @view(o.data[i, :]), i + 1
Base.next(o::DataIterator{Cols}, i) = @view(o.data[:, i]), i + 1
Base.length(o::DataIterator{Rows}) = size(o.data, 1)
Base.length(o::DataIterator{Cols}) = size(o.data, 2)

# For input==0, any input should be iterated through element by element
eachob(y, s::Series{0}, dim) = y

# For input==1, a vector is a single observation: a matrix should be iterated through by row/col
eachob(y::VectorOb,         s::Series{1}, dim) = (y,)
eachob(y::AbstractMatrix,   s::Series{1}, dim) = DataIterator(y, dim)


#--------------------------------------------------------------------------------# fit!
"""
```julia
fit!(s, y)
fit!(s, y, w)
```
Update a Series `s` with more data `y` and optional weighting `w`.
### Examples
```julia
y = randn(100)
w = rand(100)

s = Series(Mean())
fit!(s, y[1])        # one observation: use Series weight
fit!(s, y[1], w[1])  # one observation: override weight
fit!(s, y)           # multiple observations: use Series weight
fit!(s, y, w[1])     # multiple observations: override each weight with w[1]
fit!(s, y, w)        # multiple observations: y[i] uses weight w[i]
```
"""
function fit!(s::Series, y::Data, dim::ObsDimension = Rows())
    for yi in eachob(y, s, dim)
        γ = weight!(s)
        foreach(s -> fit!(s, yi, γ), s.stats)
    end
    s
end
function fit!(s::Series, y::Data, w::Float64, dim::ObsDimension = Rows())
    for yi in eachob(y, s, dim)
        updatecounter!(s)
        foreach(s -> fit!(s, yi, w), s.stats)
    end
    s
end
function fit!(s::Series, y::Data, w::Vector{Float64}, dim::ObsDimension = Rows())
    data_it = eachob(y, s, dim)
    length(w) == length(data_it) || throw(DimensionMismatch("weights don't match data length"))
    for (yi, wi) in zip(data_it, w)
        updatecounter!(s)
        foreach(s -> fit!(s, yi, wi), s.stats)
    end
    s
end
fit!(s1::T, s2::T) where {T <: Series} = merge!(s1, s2)


#-----------------------------------------------------------------------# Base
function Base.show(io::IO, s::Series)
    header(io, name(s, false, true))
    print(io, "┣━━ "); println(io, s.weight)
    print(io, "┗━━━ ┓")
    names = ifelse(isa(s.stats, Tuple), name.(s.stats), tuple(name(s.stats)))
    indent = maximum(length.(names))
    n = length(names)
    i = 0
    for o in s.stats
        i += 1
        char = ifelse(i == n, "┗━━", "┣━━")
        print(io, "\n    $char ", o)

    end
end
Base.copy(o::Series) = deepcopy(o)

#-----------------------------------------------------------------------# weight helpers
nobs(o::Series) = nobs(o.weight)
nups(o::Series) = nups(o.weight)
weight(o::Series,         n2::Int = 1) = weight(o.weight, n2)
weight!(o::Series,        n2::Int = 1) = weight!(o.weight, n2)
updatecounter!(o::Series, n2::Int = 1) = updatecounter!(o.weight, n2)

#-----------------------------------------------------------------------# merging
function Base.merge{T <: Series}(s1::T, s2::T, w::Float64)
    merge!(copy(s1), s2, w)
end
function Base.merge{T <: Series}(s1::T, s2::T, method::Symbol = :append)
    merge!(copy(s1), s2, method)
end
function Base.merge!{T <: Series}(s1::T, s2::T, method::Symbol = :append)
    n2 = nobs(s2)
    n2 == 0 && return s1
    updatecounter!(s1, n2)
    if method == :append
        merge!.(s1.stats, s2.stats, weight(s1, n2))
    elseif method == :mean
        merge!.(s1.stats, s2.stats, (weight(s1) + weight(s2)))
    elseif method == :singleton
        merge!.(s1.stats, s2.stats, weight(s1))
    else
        throw(ArgumentError("method must be :append, :mean, or :singleton"))
    end
    s1
end
function Base.merge!{T <: Series}(s1::T, s2::T, w::Float64)
    n2 = nobs(s2)
    n2 == 0 && return s1
    0 <= w <= 1 || throw(ArgumentError("weight must be between 0 and 1"))
    updatecounter!(s1, n2)
    merge!.(s1.stats, s2.stats, w)
    s1
end
