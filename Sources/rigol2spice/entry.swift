//
//  main.swift
//  rigol2spice
//
//  Created by Rui Nelson Carneiro on 05/10/2021.
//

import Foundation
import ArgumentParser

@main
struct rigol2spice: ParsableCommand {
    enum Rigol2SpiceErrors: LocalizedError {
        case outputFileNotSpeccified
        case inputFileContainsNoPoints
        
        var errorDescription: String? {
            switch self {
            case .outputFileNotSpeccified: return "Please speccify the output file name after the input file name"
            case .inputFileContainsNoPoints: return "Input file contains zero points"
            }
        }
    }
    
    @Flag(name: .shortAndLong, help: "Only list channels present in the file and quit")
    var listChannels: Bool = false
    
    @Option(name: .shortAndLong, help: "The label of the channel to be processed")
    var channel: String = "CH1"
    
    @Argument(help: "The filename of the .csv from the oscilloscope to be read", completion: CompletionKind.file(extensions: ["csv"]))
    var inputFile: String
    var inputFileExpanded: String {
        NSString(string: inputFile).expandingTildeInPath
    }
    
    @Argument(help: "The PWL filename to write to", completion: nil)
    var outputFile: String?
    var outputFileExapnded: String {
        guard let outputFile = outputFile else {
            return ""
        }
        return NSString(string: outputFile).expandingTildeInPath
    }
        
    mutating func run() throws {
        // argument validation
        if listChannels == false {
            guard outputFile != nil else {
                throw Rigol2SpiceErrors.outputFileNotSpeccified
            }
        }
        
        
        // static
        let scientificNF = NumberFormatter()
        scientificNF.numberStyle = .scientific

        let decimalNF = NumberFormatter()
        decimalNF.numberStyle = .decimal
        
        let newlineBytes = "\r\n".data(using: .ascii)!
        
        let cd = FileManager.default.currentDirectoryPath
        let cdUrl = URL(fileURLWithPath: cd)
        
        // Processing
        
        print("→ Loading input file...")
        let inputFileUrl = URL(fileURLWithPath: inputFileExpanded, relativeTo: cdUrl)

        let data = try Data(contentsOf: inputFileUrl)
        
        let numBytesString = decimalNF.string(for: data.count)!
        
        print("  " + "Read \(numBytesString) bytes")
        
        print("")
        print("→ Parsing input file...")
        var points = try CSVParser.parseCsv(data,
                                            forChannel: channel,
                                            listChannelsOnly: listChannels)
        
        guard listChannels == false else {
            return
        }
        
        guard points.isEmpty == false else {
            throw Rigol2SpiceErrors.inputFileContainsNoPoints
        }
        
        let lastTime = points.last!.time
        
        let nPointsString = decimalNF.string(for: points.count)!
        print("  " + "Points: \(nPointsString)")
        print("  " + "Last Point: \(timeNF.string(for: lastTime)!) s")
        
        // Sample rate
        if points.count >= 2 {
            let firstPointTime = points.first!.time
            let lastPointTime = points.last!.time
            let nPoints = Double(points.count)
            
            let timeInterval = (lastPointTime - firstPointTime) / (nPoints - 1)
            let sampleRate = 1 / timeInterval
            
            let timeIntervalString = timeNF.string(for: timeInterval)!
            let sampleRateString = decimalNF.string(for: sampleRate)!
            
            print("  " + "Sample 𝛥t: \(timeIntervalString) s")
            print("  " + "Sample Rate: \(sampleRateString) sa/s")
        }
        
        // Compacting...
        print("")
        print("→ Removing unecessary points...")
        let beforePoints = points.count
        points = removeUnecessary(points)
        let afterPoints = points.count
        
        print("  " + "From \(decimalNF.string(for: beforePoints)!) points to \(decimalNF.string(for: afterPoints)!) points")

        // Output
        print("")
        print("→ Writing output file...")
        let outputFileUrl = URL(fileURLWithPath: outputFileExapnded, relativeTo: cdUrl)
        
        if FileManager.default.fileExists(atPath: outputFileUrl.path) {
            try FileManager.default.removeItem(at: outputFileUrl)
        }
        
        FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)
        
        let outputFileHandle = try FileHandle(forWritingTo: outputFileUrl)
        
        for point in points {
            let pointBytes = point.serialize.data(using: .ascii)!
            outputFileHandle.write(pointBytes)
            outputFileHandle.write(newlineBytes)
        }
        outputFileHandle.closeFile()
        
        print("")
        print("Job complete ✓")
    }
}
