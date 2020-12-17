# test case to enforce consistency in joint gibbs

using Test
using IncrementalInference

##


@testset "test case with disjoint clique joint subgraph" begin

## test case with disjoint clique joint subgraph

fg = initfg()

addVariable!(fg, :x0, ContinuousEuclid{2})
addVariable!(fg, :x1, ContinuousEuclid{2})
addVariable!(fg, :x2, ContinuousEuclid{2})

initManual!(fg, :x0, randn(2,100))
initManual!(fg, :x1, randn(2,100) .+ 10)
initManual!(fg, :x2, randn(2,100) .+ 20)

addFactor!(fg , [:x0; :x1], LinearRelative(MvNormal([10.0;10], diagm([1.0;1]))))
addFactor!(fg , [:x1; :x2], LinearRelative(MvNormal([10.0;10], diagm([1.0;1]))))

# setPPE!(fg, :x2)
# fg[:x2]


##

addVariable!(fg, :x3, ContinuousEuclid{2})
addFactor!( fg, [:x2; :x3], EuclidDistance(Normal(10, 1)) )

##

addFactor!( fg, [:x0; :x3], EuclidDistance(Normal(30, 1)), graphinit=false )


##

# drawGraph(fg, show=true)

## test shortest path

# first path
tp1_ = [ :x0;:x0x1f1;:x1;:x1x2f1;:x2]
tp2_ = [ :x0;:x0x3f1;:x3;:x2x3f1;:x2]

pth = findShortestPathDijkstra(fg, :x0, :x2)
@test pth == tp1_ || pth == tp2_

pth = findShortestPathDijkstra(fg, :x0, :x2, typeFactors=[LinearRelative;])
@test pth == tp1_

# different path
pth = findShortestPathDijkstra(fg, :x0, :x2, typeFactors=[EuclidDistance;])
@test pth == tp2_


##

isHom, typeName = isPathFactorsHomogeneous(fg, :x0, :x2)

@test isHom
@test length(typeName) == 1
@test typeName[1].name == :LinearRelative



## use a specific solve order

vo = [:x3; :x1; :x2; :x0] # getEliminationOrder(fg)
tree = resetBuildTreeFromOrder!(fg, vo)

##

# drawTree(tree, show=true)

## Child clique subgraph

cliq2 = getClique(tree,:x3)
# drawGraph(cfg2, show=true)


##

cfg2 = buildCliqSubgraph(fg, cliq2)

jointmsg = IIF._generateMsgJointRelativesPriors(cfg2, cliq2)


@info "update these jointmsg test after #1010"
@test intersect( keys(jointmsg.priors) , [:x0; :x2] ) |> length == 2
@test length(jointmsg.relatives) == 0


##


# retlist = addLikelihoodsDifferentialCHILD!([:x2; :x0], cfg2)


##

tree, _, = solveTree!(fg, variableOrder=vo);


## get up message from child clique

msgBuf = IIF.getMessageBuffer(getClique(tree, :x3))
msg = msgBuf.upTx


msg.jointmsg.priors

msg.jointmsg.relatives


##




##





## check which path between separators has homogeneous factors


isHom, ftyps = isPathFactorsHomogeneous(fg, :x0, :x2)


_sft = selectFactorType(fg, :x0, :x2) 
sft = _sft()

typeof(sft).name == ftyps[1]

getindex(Main, ftyps[1])


##  dev




##

drawGraph(tfg, show=true)


##

getManifolds(LinearRelative)





#
