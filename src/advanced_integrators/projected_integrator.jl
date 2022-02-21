export projected_integrator 
#####################################################################################
# Projected API
#####################################################################################
"""
    projected_integrator(ds::DynamicalSystem, projection, complete_state; kwargs...) → integ

Return an integrator that produces iterations of the dynamical system `ds` on a
projected state space. See [Integrator API](@ref) for handling integrators.

The `projection` defines the projected space. If `projection isa AbstractVector{Int}`,
then the projected space is simply the variable indices that `projection` contains.
Otherwise, `projection` can be an arbitrary function that given the state of the
original system, returns the state in the projected space. In this case the projected
space can be equal, or even higher-dimensional than the original.

`complete_state` produces the state for the original system from the projected state.
`complete_state` can always be a function that given the projected state returns the full
state. However, if `projection isa AbstractVector{Int}`, then `complete_state` can
also be a vector that contains the values of the _remaining_ variables of the system,
i.e., those _not_ contained in the projected space. Obviously in this case
the projected space needs to be lower-dimensional than the original.

Notice that it does not have to hold that the projection is invertible,
`complete_state` is only used during [`reinit!`](@ref). The internal integrator operates
in the full state space of course, as there we know the dynamic rule and we can solve it.
The projection always happens as a last step, e.g., during [`get_state`](@ref).

## Keyword Arguments
* `u0`: initial state
* `diffeq` is a `NamedTuple` (or `Dict`) of keyword arguments propagated into
  `init` of DifferentialEquations.jl.

## Examples
Case 1: project 5-dimensional system to its last two dimensions.
```julia
ds = Systems.lorenz96(5)
projection = [4, 5]
complete_state = [0.0, 0.0, 0.0] # completed state just in the plane of last two dimensions
pinteg = projected_integrator(ds, projection, complete_state)
reinit!(pinteg, [0.2, 0.4])
step!(pinteg)
get_state(pinteg)
```
Case 2: custom projection 
```julia
ds = Systems.lorenz96(5)
projection(u) = [sum(u), sqrt(u[1]^2 + u[2]^2)]
complete_state(y) = repeat(y[1]/5, 5)
pinteg = # same as in above example...
"""
function projected_integrator(ds::DynamicalSystem, projection, complete_state;
        u0 = get_state(ds), diffeq = NamedTuple()
	)
    if projection isa AbstractVector{Int}
        @assert all(1 .≤ projection .≤ dimension(ds))
        projection = SVector(projection...)
        y = u0[projection]
    else
        @assert projection(u0) isa AbstractVector
        y = projection(u0)
    end
    if complete_state isa AbstractVector
        @assert projection isa AbstractVector{Int}
        @assert length(complete_state) + length(projection) == dimension(ds)
        remidxs = setdiff(1:dimension(ds), projection)
        @assert !isempty(remidxs)
    else
        @assert length(complete_state(y)) == dimension(ds)
        remidxs = nothing
    end
    integ = integrator(ds, u0; diffeq)
    u = zeros(dimension(ds))
	return ProjectedIntegrator(projection, complete_state, u, remidxs, integ)
end

struct ProjectedIntegrator{P, C, R, I}
    projection::P
    complete_state::C
    u::Vector{Float64} # dummy variable for a state in full state space
    remidxs::R
	integ::I
end

integrator(p::ProjectedIntegrator) = p
get_state(pinteg::ProjectedIntegrator{<:Function}) = 
    pinteg.projection(get_state(pinteg.integ))
get_state(pinteg::ProjectedIntegrator{<:SVector}) = 
    get_state(pinteg.integ)[pinteg.projection]

function SciMLBase.step!(pinteg::ProjectedIntegrator, args...)
	step!(pinteg.integ, args...)
	return
end

function Base.show(io::IO, pinteg::ProjectedIntegrator)
    println(io, "Integrator of a projected system")
    println(io,  rpad(" rule f: ", 14), DynamicalSystemsBase.eomstring(pinteg.integ.f.f))
    println(io,  rpad(" projection: ", 14), pinteg.projection)
    println(io,  rpad(" complete state: ", 14), pinteg.complete_state)
end

function SciMLBase.reinit!(pinteg::ProjectedIntegrator{P, <:AbstractVector}, y) where {P}
    u = pinteg.u
    u[pinteg.projection] .= y
    u[pinteg.remidxs] .= pinteg.complete_state
    reinit!(pinteg.integ, u)
end

function SciMLBase.reinit!(pinteg::ProjectedIntegrator{P, <:Function}, y) where {P}
    reinit!(pinteg.integ, pinteg.complete_state(y))
end