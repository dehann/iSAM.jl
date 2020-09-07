


function isCliqInitialized(cliq::TreeClique)::Bool
  return getCliqueData(cliq).initialized in [:initialized; :upsolved]
end

function isCliqUpSolved(cliq::TreeClique)::Bool
  return getCliqueData(cliq).initialized == :upsolved
end



"""
    $SIGNATURES

Return the most likely  ordering for initializing factor (assuming up solve
sequence).

Notes:
- sorts id for increasing number of connected factors.
"""
function getCliqVarInitOrderUp(tree::BayesTree, cliq::TreeClique)
  # rules to explore dimension from one to the other?

  # get all variable ids and number of associated factors
  allids = getCliqAllVarIds(cliq)
  nfcts = getCliqNumAssocFactorsPerVar(cliq)

  # get priors and singleton message variables (without partials)
  prids = getCliqVarIdsPriors(cliq, getCliqAllVarIds(cliq), false)

  # get current up msgs in the init process (now have all singletons)
  upmsgs = getMsgsUpInitChildren(tree, cliq, TreeBelief)                       # FIXME, post #459 calls?
  upmsgids = collect(keys(upmsgs))

  # all singleton variables
  singids = union(prids, upmsgids)

  # add msg marginal prior (singletons) to number of factors
  for msid in upmsgids
    nfcts[msid .== allids] .+= 1
  end

  # sort permutation order for increasing number of factor association
  nfctsp = sortperm(nfcts)
  sortedids = allids[nfctsp]

  # organize the prior variables separately with asceding factor count
  initorder = Symbol[]
  for id in sortedids
    if id in singids
      push!(initorder, id)
    end
  end
  # in ascending order of number of factors
  for id in sortedids
    if !(id in initorder)
      push!(initorder, id)
    end
  end
  return initorder
end


"""
    $SIGNATURES

Return true if clique has completed the local upward direction inference procedure.
"""
isUpInferenceComplete(cliq::TreeClique) = getCliqueData(cliq).upsolved

function areCliqVariablesAllInitialized(dfg::G, cliq::TreeClique) where {G <: AbstractDFG}
  allids = getCliqAllVarIds(cliq)
  isallinit = true
  for vid in allids
    var = DFG.getVariable(dfg, vid)
    isallinit &= isInitialized(var)
  end
  isallinit
end



"""
    $SIGNATURES

Return true if all variables in clique are considered marginalized (and initialized).
"""
function areCliqVariablesAllMarginalized(subfg::AbstractDFG,
                                         cliq::TreeClique)
  for vsym in getCliqAllVarIds(cliq)
    vert = getVariable(subfg, vsym)
    if !isMarginalized(vert) || !isInitialized(vert)
      return false
    end
  end
  return true
end




"""
    $SIGNATURES

Cycle through var order and initialize variables as possible in `subfg::AbstractDFG`.
Return true if something was updated.

Notes:
- assumed `subfg` is a subgraph containing only the factors that can be used.
  - including the required up or down messages
- intended for both up and down initialization operations.

Dev Notes
- Should monitor updates based on the number of inferred & solvable dimensions
"""
function cycleInitByVarOrder!(subfg::AbstractDFG,
                              varorder::Vector{Symbol};
                              logger=ConsoleLogger()  )::Bool
  #
  with_logger(logger) do
    @info "cycleInitByVarOrder! -- varorder=$(varorder)"
  end
  retval = false
  count = 1
  while count > 0
    count = 0
    for vsym in varorder
      var = DFG.getVariable(subfg, vsym)
      isinit = isInitialized(var)
      with_logger(logger) do
        @info "var.label=$(var.label) is initialized=$(isinit)"
      end
      doautoinit!(subfg, [var;], logger=logger)
      if isinit != isInitialized(var)
        count += 1
        retval = true
      end
    end
  end
  with_logger(logger) do
    @info "cycleInitByVarOrder!, retval=$(retval)"
  end
  flush(logger.stream)
  return retval
end


# currently for internal use only
# initialize variables based on best current achievable ordering
# OBVIOUSLY a lot of refactoring and consolidation needed with cliqGibbs / approxCliqMarginalUp
function initSolveSubFg!(subfg::AbstractDFG,
                         logger=ConsoleLogger() )
  #
  varorder = getSubFgPriorityInitOrder(subfg, logger)
  with_logger(logger) do
    @info "initSolveSubFg! -- varorder=$varorder"
  end
  cycleInitByVarOrder!(subfg, varorder, logger=logger)
  nothing
end



# Helper function for prepCliqInitMsgsDown!
# future, be used in a cached system with parent in one location only for all siblings
# this function rebuilds a local subgraph from dfg and performs the calculations of the parent here and does not wait on the CSM to perform anything.
# 4-stroke compute may render this whole function obsolete.
function condenseDownMsgsProductPrntFactors!(fgl::AbstractDFG,
                                              products::LikelihoodMessage,
                                              msgspervar::Dict{Symbol, <:AbstractVector},
                                              prnt::TreeClique,
                                              cliq::TreeClique,
                                              logger=ConsoleLogger() )
  #

  # determine the variables of interest
  reqMsgIds = collect(keys(msgspervar))
  # unique frontals per cliq
  prntvars = intersect(getCliqSeparatorVarIds(cliq), getCliqAllVarIds(prnt))
  lvarids = union(prntvars, reqMsgIds)
  # determine allowable factors, if any (only from parent cliq)
  awfcts = getCliqFactorIdsAll(prnt)
  
  # build required subgraph for parent/sibling down msgs
  lsfg = buildSubgraph(fgl, lvarids, 1; verbose=false)
  
  tempfcts = lsf(lsfg)
  dellist = setdiff(awfcts, tempfcts)
  for delf in dellist
    # TODO -- double check this deletefactor method is leaving the right parent sharing factor graph behind
    if exists(lsfg, delf)
      deleteFactor!(lsfg,delf)
    end
  end
  
  # add message priors
  addMsgFactors!(lsfg, msgspervar) # , DownwardPass
  
  # perform initialization/inference
  # FIXME, better consolidate with CSM ....uhhh TODO
  initSolveSubFg!(lsfg, logger)
  
  # extract complete downward marginal msg priors
  for id in intersect(getCliqSeparatorVarIds(cliq), lvarids)
    vari = getVariable(lsfg, id)
    products.belief[id] = TreeBelief(vari)
  end
  
  nothing
end
# # QUICK DBG CODE
# with_logger(logger) do
#     @info "condenseDownMsgsProductPrntFactors! -- reqMsgIds=$(reqMsgIds),"
#     @info "condenseDownMsgsProductPrntFactors! -- vars=$(lvarids),"
#     @info "condenseDownMsgsProductPrntFactors! -- allow factors $awfcts"
# end
# with_logger(logger) do
#     @info "condenseDownMsgsProductPrntFactors! -- lsfg fcts=$(lsf(lsfg)),"
#     @info "condenseDownMsgsProductPrntFactors! -- excess factors $dellist"
# end
  # vars = ls(lsfg)
  # len = length(vars)
  # tdims = Vector{Float64}(undef, len)
  # isinit = Vector{Bool}(undef, len)
  # for idx in 1:len
  #   tdims[idx] = getVariableSolvableDim(lsfg, vars[idx])
  #   isinit[idx] = isInitialized(lsfg, vars[idx])
  # end
  # with_logger(logger) do
  #     @info "condenseDownMsgsProductPrntFactors! -- after cycle init: vars=$vars"
  #     @info "condenseDownMsgsProductPrntFactors! -- after cycle init: tdims=$tdims"
  #     @info "condenseDownMsgsProductPrntFactors! -- after cycle init: isinit=$isinit"
  # end
  # # QUICK DBG CODE



function blockCliqUntilParentDownSolved(prnt::TreeClique; logger=ConsoleLogger())::Nothing
  #
  lbl = getLabel(prnt)

  with_logger(logger) do
    @info "blockCliqUntilParentDownSolved, prntcliq=$(prnt.index) | $lbl | going to fetch initdownchannel..."
  end
  flush(logger.stream)
  blockMsgDwnUntilStatus(prnt, :downsolved)

  return nothing
end



"""
    $SIGNATURES

Block the thread until child cliques of `prnt::TreeClique` have finished
attempting upward initialization -- i.e. have status result.
Return `::Dict{Symbol}` indicating whether next action that should be taken
for each child clique.

Notes:
- See status options at `getCliqueStatus(..)`.
- Can be called multiple times
"""
function blockCliqUntilChildrenHaveUpStatus(tree::AbstractBayesTree,
                                            prnt::TreeClique,
                                            logger=ConsoleLogger() )
  #
  ret = Dict{Int, Symbol}()
  chlr = getChildren(tree, prnt)
  for ch in chlr
    # either wait to fetch new result, or report or result
    chst = getCliqueStatus(ch)
    with_logger(logger) do
      @info "cliq $(prnt.index), child $(ch.index) status is $(chst), isready(initUpCh)=$(isready(getMsgUpChannel(ch)))."
    end
    flush(logger.stream)
    ret[ch.index] = (fetch(getMsgUpChannel(ch))).status
  end

  return ret
end

"""
    $SIGNATURES

Wait here if all siblings and the parent status are `:needdownmsg`.
Return true when parent is `:initialized` after all were `:needdownmsg`

Notes
- used for regulating long need down message chains.
- exit strategy is parent becomes status `:initialized`.
"""
function blockCliqSiblingsParentNeedDown( tree::AbstractBayesTree,
                                          cliq::TreeClique,
                                          prnt_::TreeClique; 
                                          logger=ConsoleLogger())
  #

  function doTheThing(prstat)
    with_logger(logger) do
      tt = split(string(now()), 'T')[end]
      @warn "$(tt) | $(current_task()), cliq $(cliq.index), block since all siblings/parent($(prnt_.index)) :needdownmsg."
    end
    flush(logger.stream)
    # do actual fetch
    prtmsg = fetchMsgDwnInit(prnt_).status
    with_logger(logger) do
        tt = split(string(now()), 'T')[end]
      @info "$tt | $(current_task()) clique $(prnt_.index), blockCliqSiblingsParentNeedDown -- after fetch $prstat, $prtmsg"
    end
    if prtmsg == :initialized
      return true
    else
        with_logger(logger) do
            tt = split(string(now()), 'T')[end]
            @warn "$tt | $(current_task()) Clique $(prnt_.index), maybe clear down init message $prtmsg"
        end
    end
  end


  
  allneeddwn = true
  # if length(prnt) > 0
    prstat = getCliqueStatus(prnt_)
    if prstat == :needdownmsg
      for ch in getChildren(tree, prnt_)
        chst = getCliqueStatus(ch)
        if chst != :needdownmsg
          allneeddwn = false
          break;
        end
      end

      if allneeddwn
        doTheThing(prstat)
      end
    end
  # end
  return false
end



# """
#     $SIGNATURES
#
# Perform cliq initalization calculation based on current state of the tree and factor graph,
# using upward message passing logic.
#
# Notes
# - adds msg priors added to clique subgraph
# - Return either of (:initialized, :upsolved, :needdownmsg, :badinit)
# - must use factors in cliq only, ensured by using subgraph -- TODO general case.
#
# DevNotes
# - FIXME, integrate with `8f. mustInitUpCliq_StateMachine`
# """
# function doCliqAutoInitUpPart1!(subfg::AbstractDFG,
#                                 tree::AbstractBayesTree,
#                                 cliq::TreeClique;
#                                 up_solve_if_able::Bool=true,
#                                 multiproc::Bool=true,
#                                 logger=ConsoleLogger() )
#   #
#
#   # attempt initialize if necessary
#   if !areCliqVariablesAllInitialized(subfg, cliq)
#     # structure for all up message densities computed during this initialization procedure.
#     varorder = getCliqVarInitOrderUp(tree, cliq)
#     # do physical inits, ignore cycle return value
#     cycleInitByVarOrder!(subfg, varorder, logger=logger)
#   end
#
#   return nothing
# end

function printCliqInitPartialInfo(subfg, cliq, logger=ConsoleLogger())
  varids = getCliqAllVarIds(cliq)
  initstatus = Vector{Bool}(undef, length(varids))
  initpartial = Vector{Float64}(undef, length(varids))
  for i in 1:length(varids)
    initstatus[i] = getSolverData(getVariable(subfg, varids[i])).initialized
    initpartial[i] = getSolverData(getVariable(subfg, varids[i])).inferdim
  end
  with_logger(logger) do
    tt = split(string(now()),'T')[end]
    @info "$tt, cliq $(cliq.index), PARINIT: $varids | $initstatus | $initpartial"
  end
end


"""
    $SIGNATURES

Special function to do initialization in downward direction, assuming that not all
variables can be initialized.  Relies on outside down messages.

Notes:
- assumed this `cliq` is being initialized from a previous `:needdownmsg` status.
- will use all possible local factors of cliquq in initilization process
- similar to upward initialization, but uses different message structure
  - first draft assumes upward messages will not be used,
  - full up solve still required which explicitly depends on upward messages.

Dev Notes
- Streamline add/delete msg priors from calling function and csm.
- TODO replace with nested 'minimum degree' type variable ordering.
"""
function getCliqInitVarOrderDown(dfg::AbstractDFG,
                                 cliq::TreeClique,
                                 dwnkeys::Vector{Symbol} )   # downmsgs
  #
  allsyms = getCliqAllVarIds(cliq)
  # convert input downmsg var symbols to integers (also assumed as prior beliefs)
  # make sure ids are in the clique set, since parent may have more variables.
  dwnmsgsym = intersect(dwnkeys, DFG.listVariables(dfg))
  dwnvarids = intersect(allsyms, dwnmsgsym)

  # find any other prior factors (might have partials)
  prvarids = getCliqVarIdsPriors(cliq, allsyms, true)
  hassinglids = union(dwnvarids, prvarids)

  # Get all other variable factor counts
  nfcts = getCliqNumAssocFactorsPerVar(cliq)
  # add msg marginal prior (singletons) to number of factors
  for msid in dwnmsgsym
    nfcts[msid .== allsyms] .+= 1
  end

  # sort permutation order for increasing number of factor association
  nfctsp = sortperm(nfcts)
  sortedids = allsyms[nfctsp]

  # all singleton variables
  singids = union(prvarids, dwnvarids)

  # organize the prior variables separately with asceding factor count
  initorder = Symbol[] #zeros(Int, 0)
  for id in sortedids
    if id in singids
      push!(initorder, id)
    end
  end
  # sort remaining variables for increasing associated factors
  for id in sortedids
    if !(id in initorder)
      push!(initorder, id)
    end
  end

  # return variable order
  return initorder::Vector{Symbol}
end


"""
    $SIGNATURES

Return true or false depending on whether child cliques are all up solved.
"""
function areCliqChildrenAllUpSolved(treel::AbstractBayesTree,
                                    prnt::TreeClique)::Bool
  #
  for ch in getChildren(treel, prnt)
    if !isCliqUpSolved(ch)
      return false
    end
  end
  return true
end


"""
    $SIGNATURES

Initialization requires down message passing of more specialized down init msgs.
This function performs any possible initialization of variables and retriggers
children cliques that have not yet initialized.

Notes:
- Assumed this function is only called after status from child clique up inits completed.
- Assumes cliq has parent.
  - will fetch message from parent
- Will perform down initialization if status == `:needdownmsg`.
- might be necessary to pass furhter down messges to child cliques that also `:needdownmsg`.
- Will not complete cliq solve unless all children are `:upsolved` (upward is priority).
- `dwinmsgs` assumed to come from parent initialization process.
- assume `subfg` as a subgraph that can be modified by this function (add message factors)
  - should remove message prior factors from subgraph before returning.
- May modify `cliq` values.
  - `putMsgUpInit!(cliq, msg)`
  - `setCliqueStatus!(cliq, status)`
  - `setCliqDrawColor(cliq, "sienna")`
  - `notifyCliqDownInitStatus!(cliq, status)`

Algorithm:
- determine which downward messages influence initialization order
- initialize from singletons to most connected non-singletons
- revert back to needdownmsg if cycleInit does nothing
- can only ever return :initialized or :needdownmsg status

DevNotes
- TODO Lots of cleanup required, especially from calling function.
"""
function doCliqInitDown!(subfg::AbstractDFG,
                         cliq::TreeClique,
                         initorder;
                         dbg::Bool=false,
                         logpath::String="/tmp/caesar/",
                         logger=ConsoleLogger() )
  #

  # store the cliqSubFg for later debugging
  if dbg
    DFG.saveDFG(subfg, joinpath(logpath,"logs/cliq$(cliq.index)/fg_beforedowninit"))
  end

  # cycle through vars and attempt init
  with_logger(logger) do
    @info "cliq $(cliq.index), doCliqInitDown! -- 5, cycle through vars and attempt init"
  end

  status = :needdownmsg
  if cycleInitByVarOrder!(subfg, initorder)
    status = :initialized
  end

  with_logger(logger) do
    @info "cliq $(cliq.index), doCliqInitDown! -- 6, current status: $status"
  end

  # store the cliqSubFg for later debugging
  if dbg
      DFG.saveDFG(subfg, joinpath(logpath,"logs/cliq$(cliq.index)/fg_afterdowninit"))
  end

  return status
end


"""
    $SIGNATURES

Return `true` if any of the children cliques have status `:needdownmsg`.
"""
function areCliqChildrenNeedDownMsg(children::Vector{TreeClique})::Bool
  for ch in children
    if getCliqueStatus(ch) == :needdownmsg
      return true
    end
  end
  return false
end

function areCliqChildrenNeedDownMsg(tree::AbstractBayesTree, cliq::TreeClique)::Bool
  areCliqChildrenNeedDownMsg( getChildren(tree, cliq) )
end


"""
    $SIGNATURES

Return true if has parent with status `:needdownmsg`.
"""
function isCliqParentNeedDownMsg(tree::AbstractBayesTree, cliq::TreeClique, logger=ConsoleLogger())
  prnt = getParent(tree, cliq)
  if length(prnt) == 0
    return false
  end
  prstat = getCliqueStatus(prnt[1])
  with_logger(logger) do
    @info "$(current_task()) Clique $(cliq.index), isCliqParentNeedDownMsg -- parent status: $(prstat)"
  end
  return prstat == :needdownmsg
end


# """
#    $SIGNATURES
#
# Determine if this `cliq` has been fully initialized and child cliques have completed their full upward inference.
# """
# function isCliqReadyInferenceUp(fgl::FactorGraph, tree::AbstractBayesTree, cliq::TreeClique)
#   isallinit = areCliqVariablesAllInitialized(fgl, cliq)
#
#   # check that all child cliques have also completed full up inference.
#   for chl in getChildren(tree, cliq)
#     isallinit &= isUpInferenceComplete(chl)
#   end
#   return isallinit
# end
