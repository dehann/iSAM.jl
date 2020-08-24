using Test

using DistributedFactorGraphs
using IncrementalInference


@testset "Parametric Tests" begin


##
fg = generateCanonicalFG_lineStep(7, poseEvery=1, landmarkEvery=0, posePriorsAt=collect(0:7), sightDistance=2, solverParams=SolverParams(algorithms=[:default, :parametric]))

d, result = IIF.solveFactorGraphParametric(fg)

for i in 0:7
  sym = Symbol("x",i)
  @test isapprox(d[sym].val[1], i, atol=1e-6)
end


########
fg = generateCanonicalFG_lineStep(2, graphinit=true, vardims=1, poseEvery=1, landmarkEvery=0, posePriorsAt=Int[0], sightDistance=3, solverParams=SolverParams(algorithms=[:default, :parametric]))

IIF.initParametricFrom(fg)

#
v0 = getVariable(fg,:x0)
@test isapprox(v0.solverDataDict[:parametric].val[1], 0.0, atol = 0.1)
v1 = getVariable(fg,:x1)
@test isapprox(v1.solverDataDict[:parametric].val[1], 1.0, atol = 0.1)

##
fg = generateCanonicalFG_lineStep(10, vardims=2, poseEvery=1, landmarkEvery=3, posePriorsAt=Int[0,5,10], sightDistance=3, solverParams=SolverParams(algorithms=[:default, :parametric]))
    # addFactor!(fg, [:x5; :x15], LinearConditional(Normal(10, 0.1)))
    # addFactor!(fg, [:x15; :x25], LinearConditional(Normal(10, 0.1)))

#to manually check all factors
# foreach(fct->println(fct.label, ": ", getFactorType(fct).Z), getFactors(fg))

# @profiler d,st = IIF.solveFactorGraphParametric(fg)
d,st = IIF.solveFactorGraphParametric(fg)

for i in 0:10
  sym = Symbol("x",i)
  @test isapprox(d[sym].val[1], i, atol=1e-6)
  @test isapprox(d[sym].val[2], i, atol=1e-6)
end

# print results out
if false
foreach(println, d)
end

#initialize the fg for tree to solve.
foreach(x->getSolverData(getVariable(fg,x.first),:parametric).val .= x.second.val, pairs(d))

tree = wipeBuildNewTree!(fg)#

IIF.initTreeMessageChannels!(tree)


# getSolverParams(fg).dbg=true
# getSolverParams(fg).drawtree=true
# getSolverParams(fg).async = true

tree2, smt, hist = IIF.solveTreeParametric!(fg, tree) #, recordcliqs=ls(fg))




for i in 0:10
  sym = Symbol("x",i)
  var = getVariable(fg,sym)
  val = var.solverDataDict[:parametric].val
  @test isapprox(val[1,1], i, atol=1e-6)
  @test isapprox(val[2,1], i, atol=1e-6)
end

# Print answers
if false
vsds = DFG.getSolverData.(getVariables(fg), :parametric)
foreach(v->println(v.label, ": ", DFG.getSolverData(v, :parametric).val), sort!(getVariables(fg), by=getLabel, lt=natural_lt))
end


###################################################################
fg = LightDFG{SolverParams}( solverParams=SolverParams(algorithms=[:default, :parametric]))
# fg = LightDFG{SolverParams}( solverParams=SolverParams())
N = 100
fg.solverParams.N = N
graphinit = false

addVariable!(fg, :x0, ContinuousScalar, N=N) # autoinit = graphinit
addFactor!(fg, [:x0], Prior(Normal(-1.0, 1.0)))

addVariable!(fg, :x1, ContinuousScalar, N=N) # autoinit = graphinit

addVariable!(fg, :x2, ContinuousScalar, N=N) # autoinit = graphinit
addFactor!(fg, [:x2], Prior(Normal(+1.0, 1.0)))

addFactor!(fg, [:x0; :x1], LinearConditional(Normal(0.0, 1e-1)), graphinit=graphinit)
addFactor!(fg, [:x1; :x2], LinearConditional(Normal(0.0, 1e-1)), graphinit=graphinit)




foreach(fct->println(fct.label, ": ", getFactorType(fct).Z), getFactors(fg))

d,st,vs,Σ = IIF.solveFactorGraphParametric(fg)

foreach(println, d)
@test isapprox(d[:x0].val[1], -0.01, atol=1e-4)
@test isapprox(d[:x1].val[1], 0.0, atol=1e-4)
@test isapprox(d[:x2].val[1], 0.01, atol=1e-4)

foreach(x->getSolverData(getVariable(fg,x.first),:parametric).val .= x.second.val, pairs(d))

#force message passing with manual variable order
tree = wipeBuildNewTree!(fg, variableOrder=[:x0, :x2, :x1])#

IIF.initTreeMessageChannels!(tree)

# fg.solverParams.showtree = true
# fg.solverParams.drawtree = true
# fg.solverParams.dbg = true

# task = @async begin
#   global tree2
#   global smt
#   global hist
tree2, smt, hist = IIF.solveTreeParametric!(fg, tree)
# end
foreach(v->println(v.label, ": ", DFG.getSolverData(v, :parametric).val), getVariables(fg))

@test isapprox(getVariable(fg,:x0).solverDataDict[:parametric].val[1], -0.01, atol=1e-4)
@test isapprox(getVariable(fg,:x1).solverDataDict[:parametric].val[1], 0.0, atol=1e-4)
@test isapprox(getVariable(fg,:x2).solverDataDict[:parametric].val[1], 0.01, atol=1e-4)

################################################################################
## multiple sections

fg = generateCanonicalFG_lineStep(10, poseEvery=1, landmarkEvery=10, posePriorsAt=Int[0,10], sightDistance=5, solverParams=SolverParams(algorithms=[:default, :parametric]))
# break fg in 2
deleteFactor!(fg, :x5x6f1)
# dfgplot(fg)

#check all factors
# foreach(fct->println(fct.label, ": ", getFactorType(fct).Z), getFactors(fg))

# @profiler d,st = IIF.solveFactorGraphParametric(fg)
d,st = IIF.solveFactorGraphParametric(fg)

if false
foreach(println, d)
end
for i in 0:10
  sym = Symbol("x",i)
  @test isapprox(d[sym].val[1], i, atol=1e-6)
end

foreach(x->getSolverData(getVariable(fg,x.first),:parametric).val .= x.second.val, pairs(d))

tree = wipeBuildNewTree!(fg)#

IIF.initTreeMessageChannels!(tree)

# fg.solverParams.showtree = true
# fg.solverParams.drawtree = true
# fg.solverParams.dbg = false

tree2, smt, hist = IIF.solveTreeParametric!(fg, tree)

# print results
if false
vsds = DFG.getSolverData.(getVariables(fg), :parametric)
foreach(v->println(v.label, ": ", DFG.getSolverData(v, :parametric).val), getVariables(fg))
end

for i in 0:10
  sym = Symbol("x",i)
  var = getVariable(fg,sym)
  val = var.solverDataDict[:parametric].val
  @test isapprox(val[1], i, atol=1e-6)
end


###############################################################################
#Test error prop if not converged.
#TODO Update test, it now converges

fg = generateCanonicalFG_lineStep(20, vardims=2, poseEvery=1, landmarkEvery=3, posePriorsAt=Int[0,5,10], sightDistance=3, solverParams=SolverParams(algorithms=[:default, :parametric]))

#do not initialize to force failure

tree = wipeBuildNewTree!(fg)#
IIF.initTreeMessageChannels!(tree)

# fg.solverParams.showtree = true
# fg.solverParams.drawtree = true
# fg.solverParams.dbg = true

tree2, smt, hist = IIF.solveTreeParametric!(fg, tree)

# the answers will not be correct but the tree should exit cleanly and not block


end


#
