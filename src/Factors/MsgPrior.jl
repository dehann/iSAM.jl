
"""
$(TYPEDEF)

Message prior on all dimensions of a variable node in the factor graph.

Notes
- Only temporary existance during CSM operations.
"""
struct MsgPrior{T <: SamplableBelief} <: AbstractPrior
  Z::T
  inferdim::Float64
end

# MsgPrior{T}() where {T} = new{T}()
# MsgPrior{T}(z::T, infd::R) where {T <: SamplableBelief, R <: Real} = new{T}(z, infd)
# function MsgPrior(z::T, infd::R) where {T <: SamplableBelief, R <: Real}
#     MsgPrior{T}(z, infd)
# end
function getSample(cf::CalcFactor{<:MsgPrior})
  (rand(cf.factor.Z, 1), )
end

#TODO check these for manifolds, may need updating to samplePoint
# MKD already returns a vector of points
function getSample(cf::CalcFactor{<:MsgPrior{<:ManifoldKernelDensity}})
  (rand(cf.factor.Z), )
end

getManifold(mp::MsgPrior{<:ManifoldKernelDensity}) = mp.Z.manifold


(cfo::CalcFactor{<:MsgPrior})(z, x1) = z .- x1



struct PackedMsgPrior <: PackedInferenceType
  Z::String
  inferdim::Float64
end

function convert(::Type{PackedMsgPrior}, d::MsgPrior)
  PackedMsgPrior(convert(PackedSamplableBelief, d.Z), d.inferdim)
end
function convert(::Type{<:MsgPrior}, d::PackedMsgPrior)
  MsgPrior(convert(SamplableBelief, d.Z), d.inferdim)
end

