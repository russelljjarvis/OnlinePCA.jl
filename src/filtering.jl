"""
    filtering(;input::AbstractString="", featurelist::AbstractString="", thr::Number=0, output::AbstractString=".")

This function filters the genes by some standards such as mean or variance of the genes.

Input Arguments
---------
- `input` : A Julia Binary file generated by `csv2bin` function.
- `featurelist` : A row-wise summary data such as. The CSV files are generated by `csv2bin` function.
- `thr` : The threshold to reject low-signal feature.
- `output` : The directory specified the directory you want to save the result.

Output Files
---------
- `filtered.zst` : Filtered binary file.
"""
function filtering(;input::AbstractString="", featurelist::AbstractString="", thr::Number=0, output::AbstractString=".")
    # Feature selection
    featurelist = readcsv(featurelist)
    # Setting
    if thr isa String
        thr = parse(Float64, thr)
    end
    N, M = nm(input)
    tmpN = zeros(UInt32, 1)
    tmpM = zeros(UInt32, 1)
    x = zeros(UInt32, M)
    nr = nrowfilter(input, featurelist, thr)
    open(output, "w") do file1
        stream1 = ZstdCompressorStream(file1)
        write(stream1, nr)
        write(stream1, M)
        open(input , "r") do file2
            stream2 = ZstdDecompressorStream(file2)
            read!(stream2, tmpN)
            read!(stream2, tmpM)
            progress = Progress(N)
            for n = 1:N
                read!(stream2, x)
                if featurelist[n, 1] > thr
                    write(stream1, x)
                end
                next!(progress)
            end
            close(stream2)
        end
        close(stream1)
    end
    print("\n")
end

function nrowfilter(input, featurelist, thr)
    ncol = 0
    N, M = nm(input)
    tmpN = zeros(UInt32, 1)
    tmpM = zeros(UInt32, 1)
    x = zeros(UInt32, M)
    open(input, "r") do file
        stream = ZstdDecompressorStream(file)
        read!(stream, tmpN)
        read!(stream, tmpM)
        for n = 1:N
            if featurelist[n, 1] > thr
                ncol += 1
            end
        end
        close(stream)
    end
    ncol
end
