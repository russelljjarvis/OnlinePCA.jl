"""
    svrg(;input::String="", outdir=nothing, logscale::Bool=true, pseudocount::Float64=1.0, rowmeanlist::String="", colsumlist::String="", masklist::String="", dim::Int64=3, stepsize::Float64=0.1, numepoch::Int64=5, scheduling::String="robbins-monro", g::Float64=0.9, epsilon::Float64=1.0e-8, logdir=nothing)

Online PCA solved by variance-reduced stochastic gradient descent method, also known as VR-PCA.

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
- SVRG-PCA : [Ohad Shamir, 2015](http://proceedings.mlr.press/v37/shamir15.pdf)
"""
function svrg(;input::String="", outdir=nothing, logscale::Bool=true, pseudocount::Float64=1.0, rowmeanlist::String="", colsumlist::String="", masklist::String="", dim::Int64=3, stepsize::Float64=0.1, numepoch::Int64=5, scheduling::String="robbins-monro", g::Float64=0.9, epsilon::Float64=1.0e-8, logdir=nothing)
    # Initial Setting
    N, M, pseudocount, stepsize, g, epsilon, W, v, D, rowmeanvec, colsumvec, maskvec = common_init(input, pseudocount, stepsize, g, epsilon, dim, rowmeanlist, colsumlist, masklist, logdir)

    # progress
    progress = Progress(numepoch)
    for s = 1:numepoch
        u = ∇f(W, input, D * stepsize/s, N, M, logscale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, colsumlist, colsumvec, masklist)
        Ws = W
        open(input) do file
            N = read(file, Int64)
            M = read(file, Int64)
            for n = 1:N
                # Data Import
                x = deserializex(n, file, logscale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, colsumlist, colsumvec)
                # SVRG × Robbins-Monro
                if scheduling == "robbins-monro"
                    W .= W .+ Pw(∇fn(W, x, D * stepsize/(N*(s-1)+n), M), W) .- Pw(∇fn(Ws, x, D * stepsize/(N*(s-1)+n), M), Ws) .+ u
                # SVRG × Momentum
                elseif scheduling == "momentum"
                    v .= g .* v .+ ∇fn(W, x, D * stepsize, M) .- ∇fn(Ws, x, D * stepsize, M) .+ u
                    W .= W .+ v
                # SVRG × NAG
                elseif scheduling == "nag"
                    v = g .* v + ∇fn(W - g .* v, x, D * stepsize, M) .- ∇fn(Ws, x, D * stepsize, M) .+ u
                    W .= W .+ v
                # SVRG × Adagrad
                elseif scheduling == "adagrad"
                    grad = ∇fn(W, x, D * stepsize, M) .- ∇fn(Ws, x, D * stepsize, M) .+ u
                    grad = grad / stepsize
                    v .= v .+ grad .* grad
                    W .= W .+ stepsize ./ (sqrt.(v) + epsilon) .* grad
                else
                    error("Specify the scheduling as robbins-monro, momentum, nag or adagrad")
                end

                # NaN
                if mod((N*(s-1)+n), 1000) == 0
                    if any(isnan, W)
                        error("NaN values are generated. Select other stepsize")
                    end
                end

                # Retraction
                W .= full(qrfact!(W)[:Q], thin=true)
                # save log file
                if typeof(logdir) == String
                     if(mod((N*(s-1)+n), 1000) == 0)
                        writecsv(logdir * "/W_" * string((N*(s-1)+n)) * ".csv", W)
                        writecsv(logdir * "/RecError_" * string((N*(s-1)+n)) * ".csv", RecError(W, input))
                        touch(logdir * "/W_" * string((N*(s-1)+n)) * ".csv")
                        touch(logdir * "/RecError_" * string((N*(s-1)+n)) * ".csv")
                    end
                end
            end
        end
        next!(progress)
    end

    # Return, W, λ, V
    out = WλV(W, input, dim)
    if typeof(outdir) == String
        writecsv(outdir * "/Eigen_vectors.csv", out[1])
        writecsv(outdir *"/Eigen_values.csv", out[2])
        writecsv(outdir *"/Loadings.csv", out[3])
        writecsv(outdir *"/Scores.csv", out[4])
        touch(outdir * "/Eigen_vectors.csv")
        touch(outdir *"/Eigen_values.csv")
        touch(outdir *"/Loadings.csv")
        touch(outdir *"/Scores.csv")
    end
    return out
end