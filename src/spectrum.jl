export all_states, local_basis, gibbs_tensor, brute_force
export full_spectrum, Spectrum, idx, local_basis, energy

local_basis(d::Int) = union(-1, 1:d-1)
all_states(rank::Union{Vector, NTuple}) = Iterators.product(local_basis.(rank)...)

struct Spectrum
    energies::Vector{Float64}
    states::Vector{Vector{Int}}
end

#=
function _kernel(
    energies, states, J, h
)
    L = size(J, 1)

    σ = CUDA.zeros(Int, L)
    for i = 1:L σ[i] = -1 end

    en = 0.0
    for i = 1:L
        en += h[i] #σ[i] * h[i]
        for j = 1:L en += J[i, j] end #σ[i] * J[i, j] * σ[j] end
    end

    idx = (blockIdx().x - 1) * blockDim().x + threadIdx().x
    energies[idx] = en
    states[idx] = σ
    return
end

function CUDASpectrum(ig::IsingGraph)
    L = nv(ig)
    N = 2^L

    en = CUDA.zeros(Float64, N)
    st = CUDA.Vector{Vector{Int}}(undef, N)
    J = CUDA.zeros(L, L)
    h = CUDA.zeros(L)

    copyto!(couplings(ig), J)
    copyto!(biases(ig), h)

    nb = ceil(Int, N / 256)
    @cuda threads=N blocks=nb _kernel(en, st, J, h)
    Spectrum(Array(en), Array(st))
end
=#

function Spectrum(ig::IsingGraph)
    L = nv(ig)
    N = 2^L

    energies = zeros(Float64, N)
    states = Vector{Vector{Int}}(undef, N)

    J, h = couplings(ig), biases(ig)
    Threads.@threads for i = 0:N-1
        σ = 2 .* digits(i, base=2, pad=L) .- 1
        @inbounds energies[i+1] = dot(σ, J, σ) + dot(h, σ)
        @inbounds states[i+1] = σ
    end
    Spectrum(energies, states)
end

function energy(
    σ::AbstractArray{Vector{Int}}, J::Matrix{<:Real}, h::Vector{<:Real}
)
    dot.(σ, Ref(J), σ) + dot.(Ref(h), σ)
end

function gibbs_tensor(ig::IsingGraph, β::Real=1.0)
    σ = collect.(all_states(rank_vec(ig)))
    ρ = exp.(-β .* energy(σ, couplings(ig), biases(ig)))
    ρ ./ sum(ρ)
end

function brute_force(ig::IsingGraph; num_states::Int=1)
    L = nv(ig)
    if L == 0 return Spectrum(zeros(1), Vector{Vector{Int}}[]) end
    sp = Spectrum(ig)
    num_states = min(num_states, prod(rank_vec(ig)))
    idx = partialsortperm(vec(sp.energies), 1:num_states)
    Spectrum(sp.energies[idx], sp.states[idx])
end

function full_spectrum(ig::IsingGraph; num_states::Int=1)
    if nv(ig) == 0 return Spectrum(zeros(1), Vector{Vector{Int}}[]) end
    ig_rank = rank_vec(ig)
    num_states = min(num_states, prod(ig_rank))
    σ = collect.(all_states(ig_rank))
    energies = energy(σ, couplings(ig), biases(ig))
    Spectrum(energies[begin:num_states], σ[begin:num_states])
end

function inter_cluster_energy(cl1_states, J::Matrix, cl2_states)
    hcat(collect.(cl1_states)...)' * J * hcat(collect.(cl2_states)...)
end
