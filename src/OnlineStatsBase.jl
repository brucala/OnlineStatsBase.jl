__precompile__(true)
module OnlineStatsBase

import LearnBase: value, ObsDim, ObsDimension
import StatsBase: Histogram, skewness, kurtosis, confint, coef, predict, nobs, fit!,
    AbstractWeights, Weights

export
    # Series
    Series,
    # Weight
    Weight,
    EqualWeight, ExponentialWeight, LearningRate, LearningRate2, McclainWeight,
    HarmonicWeight, Bounded, Scaled,
    # OnlineStats
    OnlineStat,
    CStat, CovMatrix, Diff, Extrema, HyperLogLog, LinReg, KMeans, Mean, Moments, MV,
    OHistogram, OrderStats, QuantileMM, QuantileMSPI, QuantileSGD, ReservoirSample, Sum, 
    Variance,
    # Other
    Bootstrap, Rows, Cols,
    # functions
    nobs, fit!, value, stats, predict, coef, replicates, confint, skewness, kurtosis,
    Weights # StatsBase.Weights, not be confused with OnlineStatsBase.Weight

#-----------------------------------------------------------------------# OnlineStat
abstract type OnlineStat{I, W} end

# Base functions
function Base.show(io::IO, o::OnlineStat)
    print(io, name(o), "(")
    showcompact(io, value(o))
    print(io, ")")
end
Base.copy(o::OnlineStat) = deepcopy(o)
function Base.:(==)(o1::T, o2::T) where {T <: OnlineStat}
    nms = fieldnames(o1)
    all(getfield.(o1, nms) .== getfield.(o2, nms))
end
Base.merge(o::T, o2::T, wt::Float64) where {T <: OnlineStat}= merge!(copy(o), o2, wt)

# OnlineStat Interface (sans `fit!`)
value(o::OnlineStat) = getfield(o, fieldnames(o)[1])
input_ndims(o::OnlineStat{I}) where {I} = I
default_weight(o::OnlineStat{I, W}) where {I, W}= W()

function input_ndims(t::Tuple)
    I = input_ndims(first(t))
    for ti in t
        input_ndims(ti) == I || error("Inputs don't match. Found: $(input_ndims.(t))")
    end
    return I
end

function default_weight(t::Tuple)
    W = default_weight(first(t))
    all(default_weight.(t) .== W) ||
        error("Weight must be specified when defaults differ: Found: $(default_weight.(t)).")
    return W
end


#-----------------------------------------------------------------------# Show helpers
function show_fields(io::IO, o)
    nms = fields_to_show(o)
    print(io, "(")
    for nm in nms
        print(io, "$nm = $(getfield(o, nm))")
        nm != nms[end] && print(io, ", ")
    end
    print(io, ")")
end

fields_to_show(o) = fieldnames(o)

header(io::IO, s::AbstractString) = println(io, "▦ $s" )

function name(o, withmodule = false, withparams = true)
    s = string(typeof(o))
    if !withmodule
        # remove text that ends in period:  OnlineStats.Mean -> Mean
        s = replace(s, r"([a-zA-Z]*\.)", "")
    end
    if !withparams
        # replace everything from "{" to the end of the string
        s = replace(s, r"\{(.*)", "")
    end
    s
end

#-----------------------------------------------------------------------# Common
smooth(x, y, γ) = x + γ * (y - x)

function smooth!(x, y, γ)
    length(x) == length(y) || 
        throw(DimensionMismatch("can't smooth arrays of different length"))
    for i in eachindex(x)
        @inbounds x[i] = smooth(x[i], y[i], γ)
    end
end

function smooth_syr!(A::AbstractMatrix, x, γ::Float64)
    size(A, 1) == length(x) || throw(DimensionMismatch())
    for j in 1:size(A, 2), i in 1:j
        @inbounds A[i, j] = (1.0 - γ) * A[i, j] + γ * x[i] * x[j]
    end
end

unbias(o) = o.nobs / (o.nobs - 1)

const ϵ = 1e-6

# (1, 0) hack
fit!(o::OnlineStat{(1,0)}, t::Tuple, γ::Float64) = fit!(o, t..., γ)

#-----------------------------------------------------------------------# includes
include("weight.jl")
include("series.jl")
include("stats.jl")
include("mv.jl")
include("bootstrap.jl")
end
