# test ScatterAlignPose2

using Test
using IncrementalInference
using Distributions


##
@testset "Test HeatmapGridDensity" begin
##


x = -10:0.1:10;
y = -10:0.1:10;

img = zeros(length(x),length(y))

g = (x,y)->pdf(MvNormal([1.0;1.0]),[x;y])

for (i,x_) in enumerate(x), (j,y_) in enumerate(y)
  img[i,j] = g(x_,y_)
end

hgd = IIF.HeatmapGridDensity(img,(x,y),nothing, 0.07, N=1000)

# check conversions to packed types
phgd = convert(PackedSamplableBelief, hgd)
hgd_ = convert(SamplableBelief, phgd)

@test isapprox( hgd, hgd_ )

# use in graph




##
end