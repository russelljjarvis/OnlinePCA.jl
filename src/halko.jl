"""
    halko(;input::AbstractString="", outdir::Union{Nothing,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="", colsumlist::AbstractString="", dim::Number=3, noversamples::Number=5, niter::Number=3, initW::Union{Nothing,AbstractString}=nothing, initV::Union{Nothing,AbstractString}=nothing, logdir::Union{Nothing,AbstractString}=nothing, perm::Bool=false)

Halko's method, which is one of randomized SVD algorithm.

Input Arguments
---------
- `input` : Julia Binary file generated by `OnlinePCA.csv2bin` function.
- `outdir` : The directory specified the directory you want to save the result.
- `scale` : {log,ftt,raw}-scaling of the value.
- `pseudocount` : The number specified to avoid NaN by log10(0) and used when `Feature_LogMeans.csv` <log10(mean+pseudocount) value of each feature> is generated.
- `rowmeanlist` : The mean of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `rowvarlist` : The variance of each row of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `colsumlist` : The sum of counts of each columns of matrix. The CSV file is generated by `OnlinePCA.sumr` functions.
- `dim` : The number of dimension of PCA.
- `noversamples` : The number of over-sampling.
- `niter` : The number of power interation.
- `initW` : The CSV file saving the initial values of eigenvectors.
- `initV` : The CSV file saving the initial values of loadings.
- `logdir` : The directory where intermediate files are saved, in every evalfreq (e.g. 5000) iteration.
- `perm` : Whether the data matrix is shuffled at random.

Output Arguments
---------
- `V` : Eigen vectors of covariance matrix (No. columns of the data matrix × dim)
- `λ` : Eigen values (dim × dim)
- `U` : Loading vectors of covariance matrix (No. rows of the data matrix × dim)
- `Scores` : Principal component scores
- `ExpVar` : Explained variance by the eigenvectors
- `TotalVar` : Total variance of the data matrix
"""
function halko(;input::AbstractString="", outdir::Union{Nothing,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="", colsumlist::AbstractString="", dim::Number=3, noversamples::Number=5, niter::Number=3, initW::Union{Nothing,AbstractString}=nothing, initV::Union{Nothing,AbstractString}=nothing, logdir::Union{Nothing,AbstractString}=nothing, perm::Bool=false)
    # Initial Setting
    pca = HALKO()
    pseudocount, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar = init(input, pseudocount, dim, rowmeanlist, rowvarlist, colsumlist, initW, initV, logdir, pca, scale)
    # Perform PCA
    out = halko(input, outdir, scale, pseudocount, rowmeanlist, rowvarlist, colsumlist, dim, noversamples, niter, logdir, pca, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, perm)
    # Output
    if outdir isa String
        writecsv(joinpath(outdir, "Eigen_vectors.csv"), out[1])
        writecsv(joinpath(outdir, "Eigen_values.csv"), out[2])
        writecsv(joinpath(outdir, "Loadings.csv"), out[3])
        writecsv(joinpath(outdir, "Scores.csv"), out[4])
        writecsv(joinpath(outdir, "ExpVar.csv"), out[5])
        writecsv(joinpath(outdir, "TotalVar.csv"), out[6])
    end
    return out
end

function halko(input, outdir, scale, pseudocount, rowmeanlist, rowvarlist, colsumlist, dim, noversamples, niter, logdir, pca, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, perm)
    N, M = nm(input)
    tmpN = zeros(UInt32, 1)
    tmpM = zeros(UInt32, 1)
    x = zeros(UInt32, M)
    normx = zeros(Float32, M)
    l = dim + noversamples
    @assert 0 < dim ≤ l ≤ min(N, M)
    Ω = rand(Float32, M, l)
    Y = zeros(Float32, N, l)
    Q = zeros(Float32, N, l)
    B = zeros(Float32, l, M)
    G = zeros(Float32, M, l)
    # If not 0 the calculation is converged
    n = 1
    println("Random Projection : Y = A Ω")
    progress = Progress(N)
    open(input) do file
        stream = ZstdDecompressorStream(file)
        read!(stream, tmpN)
        read!(stream, tmpM)
        # Each step n
        while(n <= N)
            next!(progress)
            # Row vector of data matrix
            read!(stream, x)
            normx = normalizex(x, n, stream, scale, pseudocount, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec)
            if perm
                normx .= normx[randperm(length(normx))]
            end
            # Random Projection
            Y[n,:] .= (normx'*Ω)[1,:]
            n += 1
        end
        close(stream)
    end

    if niter > 0
        # QR factorization
        println("QR factorization : Q = qr(Y)")
        Q .= Array(qr!(Y).Q)
        for i in 1:niter
            println("Subspace iterations (1/2) : qr(A' Q)")
            n = 1
            AtQ = zeros(Float32, M, l)
            progress = Progress(N)
            open(input) do file
                stream = ZstdDecompressorStream(file)
                read!(stream, tmpN)
                read!(stream, tmpM)
                # Each step n
                while(n <= N)
                    next!(progress)
                    # Row vector of data matrix
                    read!(stream, x)
                    normx = normalizex(x, n, stream, scale, pseudocount, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec)
                    if perm
                        normx .= normx[randperm(length(normx))]
                    end
                    AtQ .+= normx*Q[n,:]'
                    n += 1
                end
                close(stream)
            end
            println("qr(A' Q)")
            G .= Array(qr!(AtQ).Q)

            println("Subspace iterations (2/2) : Y = qr(A qr(A' Q))")
            n = 1
            progress = Progress(N)
            open(input) do file
                stream = ZstdDecompressorStream(file)
                read!(stream, tmpN)
                read!(stream, tmpM)
                # Each step n
                while(n <= N)
                    next!(progress)
                    # Row vector of data matrix
                    read!(stream, x)
                    normx = normalizex(x, n, stream, scale, pseudocount, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec)
                    if perm
                        normx .= normx[randperm(length(normx))]
                    end
                    Y[n,:] .= (normx'*G)[1,:]
                    n += 1
                end
                close(stream)
            end
            println("Q = qr(Y)")
            Q .= Array(qr!(Y).Q)
        end
    else
        println("QR factorization : Q = qr(Y)")
        # Renormalize with QR factorization
        Q .= Array(qr!(Y).Q)
    end

    println("Calculation of small matrix : B = Q' A")
    n = 1
    progress = Progress(N)
    open(input) do file
        stream = ZstdDecompressorStream(file)
        read!(stream, tmpN)
        read!(stream, tmpM)
        # Each step n
        while(n <= N)
            next!(progress)
            # Row vector of data matrix
            read!(stream, x)
            normx = normalizex(x, n, stream, scale, pseudocount, rowmeanlist, rowmeanvec, rowvarlist, rowvarvec, colsumlist, colsumvec)
            if perm
                normx .= normx[randperm(length(normx))]
            end
            B .+= Q[n,:]*normx'
            n += 1
        end
        close(stream)
    end
    # SVD with small matrix
    println("SVD with small matrix : svd(B)")
    W, σ, V = svd(B)
    U = Q*W
    λ = σ .* σ ./ M
    # PC scores, Explained Variance
    Scores = zeros(Float32, M, dim)
    for n = 1:dim
        Scores[:, n] .= λ[n] .* V[:, n]
    end
    ExpVar = sum(λ) / TotalVar
    # Return
    return (V[:,1:dim], λ[1:dim], U[:,1:dim], Scores[:,1:dim], ExpVar, TotalVar)
end
