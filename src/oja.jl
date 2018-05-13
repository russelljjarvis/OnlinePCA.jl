"""
    oja(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, logscale::Bool=true, pseudocount::Number=1.0, rowmeanlist::AbstractString="", colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=5, scheduling::AbstractString="robbins-monro", g::Number=0.9, epsilon::Number=1.0e-8, logdir::Union{Void,AbstractString}=nothing)
Online PCA solved by stochastic gradient descent method, also known as Oja's method.
Input Arguments
---------
- `input` : Julia Binary file generated by `OnlinePCA.csv2sl` function.
- `outdir` : The directory specified the directory you want to save the result.
- `logscale`  : Whether the count value is converted to log10(x + pseudocount).
- `pseudocount` : The number specified to avoid NaN by log10(0) and used when `Feature_LogMeans.csv` <log10(mean+pseudocount) value of each feature> is generated.
- `rowmeanlist` : The mean of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `colsumlist` : The sum of counts of each columns of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `masklist` : The column list that user actually analyze.
- `dim` : The number of dimension of PCA.
- `stepsize` : The parameter used in every iteration.
- `numepoch` : The number of epoch.
- `scheduling` : Learning parameter scheduling. `robbins-monro`, `momentum`, `nag`, and `adagrad` are available.
- `g` : The parameter that is used when scheduling is specified as nag.
- `epsilon` : The parameter that is used when scheduling is specified as adagrad.
- `logdir` : The directory where intermediate files are saved, in every 1000 iteration.
Output Arguments
---------
- `W` : Eigen vectors of covariance matrix (No. columns of the data matrix × dim)
- `λ` : Eigen values (dim × dim)
- `V` : Loading vectors of covariance matrix (No. rows of the data matrix × dim)
Reference
---------
- SGD-PCA（Oja's method) : [Erkki Oja et. al., 1985](https://www.sciencedirect.com/science/article/pii/0022247X85901313), [Erkki Oja, 1992](https://www.sciencedirect.com/science/article/pii/S0893608005800899)
"""
function oja(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, logscale::Bool=true, pseudocount::Number=1.0, rowmeanlist::AbstractString="", colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=5, scheduling::AbstractString="robbins-monro", g::Number=0.9, epsilon::Number=1.0e-8, logdir::Union{Void,AbstractString}=nothing)
    # Initial Setting
    pca = OJA()
    if scheduling == "robbins-monro"
        scheduling = ROBBINS_MONRO()
    elseif scheduling == "momentum"
        scheduling = MOMENTUM()
    elseif scheduling == "nag"
        scheduling = NAG()
    elseif scheduling == "adagrad"
        scheduling = ADAGRAD()
    else
        error("Specify the scheduling as robbins-monro, momentum, nag or adagrad")
    end
    pseudocount, stepsize, g, epsilon, W, v, D, rowmeanvec, colsumvec, maskvec, N, M, AllVar = init(input, pseudocount, stepsize, g, epsilon, dim, rowmeanlist, colsumlist, masklist, logdir, pca, logscale)
    # Perform PCA
    out = oja(input, outdir, logscale, pseudocount, rowmeanlist, colsumlist, masklist, dim, stepsize, numepoch, scheduling, g, epsilon, logdir, pca, W, v, D, rowmeanvec, colsumvec, maskvec, N, M, AllVar)
    if typeof(outdir) == String
        output(outdir, out)
    end
    return out
end

function oja(input, outdir, logscale, pseudocount, rowmeanlist, colsumlist, masklist, dim, stepsize, numepoch, scheduling, g, epsilon, logdir, pca, W, v, D, rowmeanvec, colsumvec, maskvec, N, M, AllVar)
    # Each epoch s
    progress = Progress(numepoch)
    for s = 1:numepoch
        open(input) do file
            N = read(file, Int64)
            M = read(file, Int64)
            # Each step n
            for n = 1:N
                # Row vector of data matrix
                x = deserializex(n, file, logscale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, colsumlist, colsumvec)
                # Update Eigen vector
                W, v = ojaupdate(scheduling, stepsize, g, epsilon, D, N, M, W, v, x, s, n)
                # NaN
                checkNaN(N, s, n, W, pca)
                # Retraction
                W .= full(qrfact!(W)[:Q], thin=true)
                # save log file
                if typeof(logdir) == String
                    outputlog(N, s, n, input, logdir, W, pca, AllVar, logscale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, colsumlist, colsumvec)
                end
            end
        end
        next!(progress)
    end

    # Return, W, λ, V
    WλV(W, input, dim)
end

# Oja × Robbins-Monro
function ojaupdate(scheduling::ROBBINS_MONRO, stepsize, g, epsilon, D, N, M, W, v, x, s, n)
    W .= W .+ ∇fn(W, x, D , M, stepsize/(N*(s-1)+n))
    v = nothing
    return W, v
end

# Oja × Momentum
function ojaupdate(scheduling::MOMENTUM, stepsize, g, epsilon, D, N, M, W, v, x, s, n)
    v .= g .* v .+ ∇fn(W, x, D, M, stepsize)
    W .= W .+ v
    return W, v
end

# Oja × NAG
function ojaupdate(scheduling::NAG, stepsize, g, epsilon, D, N, M, W, v, x, s, n)
    v = g .* v + ∇fn(W - g .* v, x, D, M, stepsize)
    W .= W .+ v
    return W, v
end

# Oja × Adagrad
function ojaupdate(scheduling::ADAGRAD, stepsize, g, epsilon, D, N, M, W, v, x, s, n)
    grad = ∇fn(W, x, D, M, stepsize)
    grad = grad / stepsize
    v .= v .+ grad .* grad
    W .= W .+ stepsize ./ (sqrt.(v) + epsilon) .* grad
    return W, v
end