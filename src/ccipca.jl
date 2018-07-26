"""
    ccipca(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="",colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=3, stop::Number=1.0e-3, evalfreq::Number=5000, offsetFull::Number=1f-20, offsetStoch::Number=1f-6, logdir::Union{Void,AbstractString}=nothing)

Online PCA solved by candid covariance-free incremental PCA.

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
- `logdir` : The directory where intermediate files are saved, in every 1000 iteration.

Output Arguments
---------
- `W` : Eigen vectors of covariance matrix (No. columns of the data matrix × dim)
- `λ` : Eigen values (dim × dim)
- `V` : Loading vectors of covariance matrix (No. rows of the data matrix × dim)

Reference
---------
- CCIPCA : [Juyang Weng et. al., 2003](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.7.5665&rep=rep1&type=pdf)
"""
function ccipca(;input::AbstractString="", outdir::Union{Void,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="",colsumlist::AbstractString="", masklist::AbstractString="", dim::Number=3, stepsize::Number=0.1, numepoch::Number=3, stop::Number=1.0e-3, evalfreq::Number=5000, offsetFull::Number=1f-20, offsetStoch::Number=1f-6, logdir::Union{Void,AbstractString}=nothing)
    # Initial Setting
    pca = CCIPCA()
    N, M = nm(input)
    pseudocount, stepsize, W, X, D, rowmeanvec, rowvarvec, colsumvec, maskvec, N, M, AllVar, stop, evalfreq, offsetFull, offsetStoch = init(input, pseudocount, stepsize, dim, rowmeanlist, rowvarlist, colsumlist, masklist, logdir, pca, stop, evalfreq, offsetFull, offsetStoch, scale)
    tmpN = zeros(UInt32, 1)
    tmpM = zeros(UInt32, 1)
    x = zeros(UInt32, M)
    normx = zeros(Float32, M)
    # If true the calculation is converged
    conv = false
    s = 1
    n = 1
    # Each epoch s
    progress = Progress(numepoch*N)
    while(!conv && s <= numepoch)
        open(input) do file
            stream = ZstdDecompressorStream(file)
            read!(stream, tmpN)
            read!(stream, tmpM)
            # Each step n
            while(!conv && n <= N)
                # Row vector of data matrix
                read!(stream, x)
                normx = normalizex(x, n, stream, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec)
                if norm(normx) == 0
                    tmp_normx = rand(Float32, M)
                    X[:, 1] = tmp_normx / Float32(norm(tmp_normx))
                else
                    X[:, 1] = normx
                end
                # CCIPCA
                k = N * (s - 1) + n
                for i = 1:min(dim, k)
                    if i == k
                        W[:, i] = X[:, i]
                    else
                        w1 = (k - 1 - stepsize) / k
                        w2 = (1 + stepsize) / k
                        Wi = W[:, i]
                        Xi = X[:, i]
                        W[:, i] = w1 * Wi + Xi * dot(w2 * Xi * offsetStoch, Wi/norm(Wi)) / offsetStoch
                        # Data for calculating i+1 th Eigen vector
                        Wi = W[:, i]
                        Wnorm = Wi / norm(Wi)
                        X[:, i+1] = Xi - dot(Xi * offsetStoch, Wnorm) * Wnorm / offsetStoch
                    end
                end
                # NaN
                checkNaN(N, s, n, W, evalfreq, pca)
                # Check Float32
                @assert W[1,1] isa Float32
                # Normalization
                for i=1:dim
                    W[:, i] = W[:, i] / norm(W[:, i])
                end
                # save log file
                if logdir isa String
                    conv = outputlog(N, s, n, input, dim, logdir, W, pca, AllVar, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, stop, conv, evalfreq)
                end
                n = n + 1
                next!(progress)
            end
            close(stream)
        end
        # save log file
        if logdir isa String
            conv = outputlog(s, input, dim, logdir, W, GD(), AllVar, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec, stop, conv)
        end
        s = s + 1
        if n == N + 1
            n = 1
        end
    end

    # Return, W, λ, V
    out = WλV(W, input, dim, scale, pseudocount, masklist, maskvec, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec)
    if outdir isa String
        output(outdir, out)
    end
    return out
end