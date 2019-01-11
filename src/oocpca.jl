"""
    oocpca(;input::AbstractString="", outdir::Union{Nothing,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="", colsumlist::AbstractString="", dim::Number=3, initW::Union{Nothing,AbstractString}=nothing, initV::Union{Nothing,AbstractString}=nothing, logdir::Union{Nothing,AbstractString}=nothing, perm::Bool=false)

Out-of-core PCA.

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
"""
function oocpca(;input::AbstractString="", outdir::Union{Nothing,AbstractString}=nothing, scale::AbstractString="ftt", pseudocount::Number=1.0, rowmeanlist::AbstractString="", rowvarlist::AbstractString="", colsumlist::AbstractString="", dim::Number=3, initW::Union{Nothing,AbstractString}=nothing, initV::Union{Nothing,AbstractString}=nothing, logdir::Union{Nothing,AbstractString}=nothing, perm::Bool=false)
    # Initial Setting
    pca = OOCPCA()
    pseudocount, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar = init(input, pseudocount, dim, rowmeanlist, rowvarlist, colsumlist, initW, initV, logdir, pca, scale)
    # Perform PCA
    out = oocpca(input, outdir, scale, pseudocount, rowmeanlist, rowvarlist, colsumlist, dim, logdir, pca, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, perm)
    # Output
    if outdir isa String
        writecsv(joinpath(outdir, "Eigen_vectors.csv"), out[1])
        writecsv(joinpath(outdir, "Eigen_values.csv"), out[2])
        writecsv(joinpath(outdir, "Loadings.csv"), out[3])
        writecsv(joinpath(outdir, "Scores.csv"), out[4])
        writecsv(joinpath(outdir, "ExpVar.csv"), out[5])
    end
    return out
end

function oocpca(input, outdir, scale, pseudocount, rowmeanlist, rowvarlist, colsumlist, dim, logdir, pca, W, D, rowmeanvec, rowvarvec, colsumvec, N, M, TotalVar, perm)
    N, M = nm(input)
    tmpN = zeros(UInt32, 1)
    tmpM = zeros(UInt32, 1)
    x = zeros(UInt32, M)
    normx = zeros(Float32, M)
    l = dim + 5
    its = 3
    @assert 0 < dim ≤ l ≤ min(N, M)
    Ω = rand(Float32, M, l)
    Y = rand(Float32, N, l)
    B = zeros(Float32, l, M)
    # If not 0 the calculation is converged
    n = 1
    # Each epoch s
    println("Random Projection : A*Ω")
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
            tmpY = normx'*Ω
            @inbounds for i in 1:size(tmpY)[2]
                Y[n,i] = tmpY[1,i]
            end
            n += 1
        end
        close(stream)
    end
    # Renormalize with LU factorization
    F = lu!(Y)

    for i in 1:its
        println("Renormalization : A^T * L")
        n = 1
        AtL = zeros(Float32, M, l)
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
                AtL = AtL .+ normx*F.L[n,:]'
                n += 1
            end
            close(stream)
        end

        println("Renormalization : A * A^T * L")
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
                @inbounds for i in 1:size(AtL)[2]
                    Y[n,i] = normx'*AtL[:,i]
                end
                n += 1
            end
            close(stream)
        end
        if i < its
            # Renormalize with LU factorization
            F = lu!(Y)
        else
            # Renormalize with QR factorization
            F = qr!(Y)
        end
    end

    println("Calculation of small matrix : Q'A")
    Q = Matrix(F.Q)
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
            B = B .+ Q[n,:]*normx'
            n += 1
        end
        close(stream)
    end
    # SVD with small matrix
    println("SVD with small matrix : svd(Q'A)")
    W, λ, V = svd(B)
    U = Q*W
    # PC scores, Explained Variance
    Scores = zeros(Float32, M, dim)
    for n = 1:dim
        Scores[:, n] .= λ[n] .* V[:, n]
    end
    ExpVar = sum(λ) / TotalVar
    # Return
    return (V[:,1:dim], λ[1:dim], U[:,1:dim], Scores[:,1:dim], ExpVar)
end
