"""
    gd(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="",colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=3, scheduling::AbstractString="robbins-monro", g::Number=0.9, epsilon::Number=1.0e-8, stop::Number=1.0e-3, evalfreq::Number=5000, offsetFull::Number=1f-20, offsetStoch::Number=1f-6, logdir::Union{Void,AbstractString}=nothing)


Online PCA solved by gradient descent method.

The convergence is relatively slower than the other online PCA methods.

Input Arguments
---------
- `input` : Julia Binary file generated by `OnlinePCA.csv2bin` function.
- `outdir` : The directory specified the directory you want to save the result.
- `scale` : {log,ftt,raw}-scaling of the value.
- `pseudocount` : The number specified to avoid NaN by log10(0) and used when `Feature_LogMeans.csv` <log10(mean+pseudocount) value of each feature> is generated.
- `rowmeanlist` : The mean of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `rowvarlist` : The variance of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
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
"""
function gd(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="",colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=3, scheduling::AbstractString="robbins-monro", g::Number=0.9, epsilon::Number=1.0e-8, stop::Number=1.0e-3, evalfreq::Number=5000, offsetFull::Number=1f-20, offsetStoch::Number=1f-6, logdir::Union{Void,AbstractString}=nothing)
    # Initial Setting
    pca = GD()
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
    pseudocount, stepsize, g, epsilon, W, v, D, rowmeanvec, rowvarvec, colsumvec, maskvec, N, M, AllVar, stop, evalfreq, offsetFull, offsetStoch = init(input, pseudocount, stepsize, g, epsilon, dim, rowmeanlist, rowvarlist, colsumlist, masklist, logdir, pca, stop, evalfreq, offsetFull, offsetStoch, scale)
    # Perform PCA
    out = gd(input, outdir, scale, pseudocount, rowmeanlist, rowvarlist, colsumlist, masklist, dim, stepsize, numepoch, scheduling, g, epsilon, logdir, pca, W, v, D, rowmeanvec, rowvarvec, colsumvec, maskvec, N, M, AllVar, stop, evalfreq, offsetFull, offsetStoch)
    if outdir isa String
        output(outdir, out)
    end
    return out
end

function gd(input, outdir, scale, pseudocount, rowmeanlist, rowvarlist, colsumlist, masklist, dim, stepsize, numepoch, scheduling, g, epsilon, logdir, pca, W, v, D, rowmeanvec, rowvarvec, colsumvec, maskvec, N, M, AllVar, stop, evalfreq, offsetFull, offsetStoch)
    # If true the calculation is converged
    conv = false
    s = 1
    n = 1
    # Each epoch s
    progress = Progress(numepoch)
    while(!conv && s <= numepoch)
        # Update Eigen vector
        W, v = gdupdate(scheduling, stepsize, g, epsilon, D, N, M, W, v, s, input, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, offsetFull, offsetStoch)
        # NaN
        checkNaN(W, pca)
        # Retraction
        W .= full(qrfact!(W)[:Q], thin=true)
        # save log file
        if logdir isa String
            conv = outputlog(s, input, dim, logdir, W, pca, AllVar, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, stop, conv)
        end
        # next!(progress)
        s = s + 1
    end

    # Return, W, λ, V
    WλV(W, input, dim, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec)
end

# GD × Robbins-Monro
function gdupdate(scheduling::ROBBINS_MONRO, stepsize, g, epsilon, D, N, M, W, v, s, input, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, offsetFull, offsetStoch)
    W .= W .+ ∇f(W, input, D, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, stepsize/s, offsetFull, offsetStoch)
    v = nothing
    return W, v
end

# GD × Momentum
function gdupdate(scheduling::MOMENTUM, stepsize, g, epsilon, D, N, M, W, v, s, input, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, offsetFull, offsetStoch)
    v .= g .* v .+ ∇f(W, input, D, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, stepsize/s, offsetFull, offsetStoch)
    W .= W .+ v
    return W, v
end

# GD × NAG
function gdupdate(scheduling::NAG, stepsize, g, epsilon, D, N, M, W, v, s, input, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, offsetFull, offsetStoch)
    v = g .* v + ∇f(W - g .* v, input, D, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, stepsize/s, offsetFull, offsetStoch)
    W .= W .+ v
    return W, v
end

# GD × Adagrad
function gdupdate(scheduling::ADAGRAD, stepsize, g, epsilon, D, N, M, W, v, s, input, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, offsetFull, offsetStoch)
    grad = ∇f(W, input, D, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, stepsize/s, offsetFull, offsetStoch)
    grad = grad / stepsize
    v .= v .+ grad .* grad
    W .= W .+ stepsize ./ (sqrt.(v) + epsilon) .* grad
    return W, v
end