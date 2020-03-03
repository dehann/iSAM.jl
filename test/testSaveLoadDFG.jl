
using IncrementalInference
using Test

@testset "saving to and loading from FileDFG" begin

  fg = generateCanonicalFG_Kaess()
  addVariable!(fg, :x4, ContinuousScalar)
  addFactor!(fg, [:x2;:x3;:x4], LinearConditional(Normal())multihypo=[1.0;0.6;0.4])

  saveFolder = "/tmp/dfg_test"
  saveDFG(fg, saveFolder) #, compress= VERSION < v"1.1" ? :none : :gzip)
  # VERSION above 1.0.x hack required since Julia 1.0 does not seem to havfunction `splitpath`
  if v"1.1" <= VERSION
    retDFG = initfg() # LightDFG{SolverParams}(params=SolverParams())
    retDFG = loadDFG(saveFolder, IncrementalInference, retDFG)
    @test symdiff(ls(fg), ls(retDFG)) == []
    @test symdiff(lsf(fg), lsf(retDFG)) == []

    @test getFactor(fg, :x2x3x4f1).solverData.multihypo - getFactor(retDFG:x2x3x4f1).solverData.multihypo |> norm < 1e-10
  end

end
