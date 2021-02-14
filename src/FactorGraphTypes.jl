import Base: convert
import Base: ==



const BeliefArray{T} = Union{Array{T,2}, Adjoint{T, Array{T,2}} }

abstract type _AbstractThreadModel end

"""
$(TYPEDEF)
"""
struct SingleThreaded <: _AbstractThreadModel
end
"""
$(TYPEDEF)
"""
struct MultiThreaded <: _AbstractThreadModel
end


"""
$(TYPEDEF)

Solver parameters for the DistributedFactoGraph.

Dev Notes
- FIXME change to using kwargs from Parameters.jl
- TODO remove NothingUnion
- TODO Upgrade to common @kwargs struct approach
"""
mutable struct SolverParams <: DFG.AbstractParams
  dimID::Int
  # TODO remove NothingUnion
  registeredModuleFunctions::NothingUnion{Dict{Symbol, Function}} # remove from
  reference::NothingUnion{Dict{Symbol, Tuple{Symbol, Vector{Float64}}}}
  stateless::Bool
  qfl::Int # Quasi fixed length
  isfixedlag::Bool # true when adhering to qfl window size for solves
  limitfixeddown::Bool # if true, then fixed lag will also not update marginalized during down (default false)
  # new functions
  incremental::Bool
  useMsgLikelihoods::Bool
  upsolve::Bool
  downsolve::Bool
  drawtree::Bool
  drawCSMIters::Bool
  showtree::Bool
  drawtreerate::Float64
  dbg::Bool
  async::Bool
  limititers::Int
  N::Int
  multiproc::Bool
  logpath::String
  graphinit::Bool
  treeinit::Bool # still experimental with known errors
  limittreeinit_iters::Int
  algorithms::Vector{Symbol} # list of algorithms to run [:default] is mmisam
  spreadNH::Float64 # experimental, entropy spread adjustment used for both null hypo cases.
  inflation::Float64 # experimental, how much to disperse particles before convolution solves, #1051
  maxincidence::Int # maximum incidence to a variable in an effort to enhance sparsity
  alwaysFreshMeasurements::Bool
  devParams::Dict{Symbol,String}
  #
end

SolverParams(;dimID::Int=0,
              registeredModuleFunctions=nothing,
              reference=nothing,
              stateless::Bool=false,
              qfl::Int=99999999999,
              isfixedlag::Bool=false,
              limitfixeddown::Bool=false,
              incremental::Bool=true,
              useMsgLikelihoods::Bool=true,
              upsolve::Bool=true,
              downsolve::Bool=true,
              drawtree::Bool=false,
              drawCSMIters::Bool=true,
              showtree::Bool=false,
              drawtreerate::Float64=0.5,
              dbg::Bool=false,
              async::Bool=false,
              limititers::Int=500,
              N::Int=100,
              multiproc::Bool=1 < nprocs(),
              logpath::String="/tmp/caesar/$(now())",
              graphinit::Bool=true,
              treeinit::Bool=false,
              limittreeinit_iters::Int=10,
              algorithms::Vector{Symbol}=[:default],
              spreadNH::Real=3.0,
              inflation::Real=3.0,
              maxincidence::Int=500,
              alwaysFreshMeasurements::Bool=true,
              devParams::Dict{Symbol,String}=Dict{Symbol,String}()
            ) = SolverParams( dimID,
                              registeredModuleFunctions,
                              reference,
                              stateless,
                              qfl,
                              isfixedlag,
                              limitfixeddown,
                              incremental,
                              useMsgLikelihoods,
                              upsolve,
                              downsolve,
                              drawtree,
                              drawCSMIters,
                              showtree,
                              drawtreerate,
                              dbg,
                              async,
                              limititers,
                              N,
                              multiproc,
                              logpath,
                              graphinit,
                              treeinit,
                              limittreeinit_iters,
                              algorithms,
                              spreadNH,
                              inflation,
                              maxincidence,
                              alwaysFreshMeasurements,
                              devParams )
#


"""
$(TYPEDEF)

Notes
- type-stable `usercache`, see https://github.com/JuliaRobotics/IncrementalInference.jl/issues/783#issuecomment-665080114 

DevNotes
- TODO why not just a NamedTuple? Perhaps part of #467
- TODO better consolidate with CCW, CPT, CalcFactor
- TODO standardize -- #927, #1025, #784, #692, #640
- TODO make immutable #825
"""
mutable struct FactorMetadata{FV<:AbstractVector{<:DFGVariable}, 
                              VL<:AbstractVector{Symbol}, 
                              AR<:AbstractVector{<:AbstractArray}, 
                              CD}
  # full list of Vector{DFGVariable} connected to the factor
  fullvariables::FV # Vector{<:DFGVariable}
  #TODO full variable can perhaps replace this
  variablelist::VL # Vector{Symbol} 
  # TODO consolidate, same as ARR used in CCW,
  arrRef::AR # Vector{Matrix{Float64}}
  # label of which variable is being solved for
  solvefor::Symbol       
  # for type specific user data, see (? #784)
  cachedata::CD
end

"""
$(TYPEDEF)

DevNotes
- FIXME consolidate with CalcFactor
- TODO consolidate with CCW, FMd, CalcFactor
- TODO consider renaming `.p` to `.decisionDims`
  - TODO `.decisionDims::DD where DD <: Union{<:AbstractVector{Int},Colon}` -- ensure type stability
- TODO figure out if we want static parameter THRID
- TODO make static params {XDIM, ZDIM, P}
- TODO make immutable
"""
mutable struct ConvPerThread{R,F<:FactorMetadata}
  thrid_::Int
  # the actual particle being solved at this moment
  particleidx::Int
  # additional/optional data passed to user function
  factormetadata::F
  # subsection indices to select which params should be used for this hypothesis evaluation
  activehypo::Vector{Int}
  # Select which decision variables to include in a particular optimization run
  p::Vector{Int}
  # slight numerical perturbation for degenerate solver cases such as division by zero
  perturb::Vector{Float64}
  # working memory location for optimization routines on target decision variables
  X::Array{Float64,2}
  # working memory to store residual for optimization routines
  res::R # was Vector{Float64}
end

"""
$(TYPEDEF)
"""
mutable struct CommonConvWrapper{ T<:FunctorInferenceType,
                                  H<:Union{Nothing, Distributions.Categorical},
                                  C<:Union{Nothing, Vector{Int}} } <: FactorOperationalMemory
  #
  ### Values consistent across all threads during approx convolution
  usrfnc!::T # user factor / function
  # general setup
  xDim::Int
  zDim::Int
  # special case settings
  specialzDim::Bool # is there a special zDim requirement -- defined by user
  partial::Bool # is this a partial constraint -- defined by user
  # multi hypothesis settings
  hypotheses::H # categorical to select which hypothesis is being considered during convolution operation
  certainhypo::C
  nullhypo::Float64
  # values specific to one complete convolution operation
  params::Vector{Array{Float64,2}} # parameters passed to each hypothesis evaluation event on user function
  varidx::Int # which index is being solved for in params?
  # FIXME make type stable
  measurement::Tuple # user defined measurement values for each approxConv operation
  threadmodel::Type{<:_AbstractThreadModel} # Union{Type{SingleThreaded}, Type{MultiThreaded}}
  ### particular convolution computation values per particle idx (varies by thread)
  cpt::Vector{<:ConvPerThread}
  # inflationSpread
  inflation::Float64
end



function ConvPerThread( X::Array{Float64,2},
                        zDim::Int,
                        factormetadata::FactorMetadata;
                        particleidx::Int=1,
                        activehypo= 1:length(params),
                        p=collect(1:size(X,1)),
                        perturb=zeros(zDim),
                        res=zeros(zDim),
                        thrid_ = 0  )
  #
  return ConvPerThread( thrid_,
                        particleidx,
                        factormetadata,
                        Int[activehypo;],
                        p,
                        perturb,
                        X,
                        res)
end


function CommonConvWrapper( fnc::T,
                            X::Array{Float64,2},
                            zDim::Int,
                            params::Vector{Array{Float64,2}},
                            factormetadata::FactorMetadata;
                            specialzDim::Bool=false,
                            partial::Bool=false,
                            hypotheses::H=nothing,
                            certainhypo=nothing,
                            activehypo= 1:length(params),
                            nullhypo::Real=0,
                            varidx::Int=1,
                            measurement::Tuple=(zeros(0,1),),
                            particleidx::Int=1,
                            p=collect(1:size(X,1)),
                            perturb=zeros(zDim),
                            xDim::Int=size(X,1),
                            res::AbstractVector{<:Real}=zeros(zDim),
                            threadmodel::Type{<:_AbstractThreadModel}=MultiThreaded,
                            inflation::Real=0.0  ) where {T<:FunctorInferenceType,H}
  #
  return  CommonConvWrapper(fnc,
                            xDim,
                            zDim,
                            specialzDim,
                            partial,
                            hypotheses,
                            certainhypo,
                            Float64(nullhypo),
                            params,
                            varidx,
                            measurement,
                            threadmodel,
                            (i->ConvPerThread(X, zDim,factormetadata, particleidx=particleidx,
                                              activehypo=activehypo, p=p, 
                                              perturb=perturb, res=res )).(1:Threads.nthreads()),
                            inflation
                            )
end



#
