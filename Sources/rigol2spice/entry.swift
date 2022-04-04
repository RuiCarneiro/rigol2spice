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
        case outputFileAlreadyExists(filePath: String)
        case outputFileNotSpeccified
        case inputFileContainsNoPoints
        
        var errorDescription: String? {
            switch self {
            case .outputFileAlreadyExists(filePath: let path): return "The file \(path) already exists, will not overwrite"
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
            
            guard FileManager.default.fileExists(atPath: outputFileExapnded) == false else {
                throw Rigol2SpiceErrors.outputFileAlreadyExists(filePath: outputFileExapnded)
            }
        }
        
        
        // static
        let nf = NumberFormatter()
        nf.numberStyle = .scientific

        let nf2 = NumberFormatter()
        nf2.numberStyle = .decimal
        
        let newlineBytes = "\r\n".data(using: .ascii)!
        
        let cd = FileManager.default.currentDirectoryPath
        let cdUrl = URL(fileURLWithPath: cd)
        
        // Processing
        
        print("1. Reading input file...")
        let inputFileUrl = URL(fileURLWithPath: inputFileExpanded, relativeTo: cdUrl)

        let data = try Data(contentsOf: inputFileUrl)
        
        let numBytesString = nf2.string(for: data.count)!
        
        print("  " + "Read \(numBytesString) bytes")
        
        print("2. Parsing input file...")
        let points = try CSVParser.parseCsv(data,
                                            forChannel: channel,
                                            listChannelsOnly: listChannels)
        
        guard listChannels == false else {
            return
        }
        
        guard points.isEmpty == false else {
            throw Rigol2SpiceErrors.inputFileContainsNoPoints
        }
        
        let lastTime = points.last!.time
        
        let nPointsString = nf2.string(for: points.count)!
        print("  " + "Points: \(nPointsString)")
        print("  " + "Last Point: \(nf.string(fromDecimal: lastTime)!) s")
        
        // Sample rate
        if points.count >= 2 {
            let firstPointTime = points.first!.time
            let lastPointTime = points.last!.time
            let nPoints = Decimal(points.count)
            
            let timeInterval = (lastPointTime - firstPointTime) / (nPoints - 1)
            let sampleRate = 1 / timeInterval
            
            let timeIntervalString = nf.string(fromDecimal: timeInterval) ?? ""
            let sampleRateString = nf2.string(fromDecimal: sampleRate) ?? ""
            
            print("  " + "Sample 𝛥t: \(timeIntervalString) s")
            print("  " + "Sample Rate: \(sampleRateString) sa/s")
        }
        

        // Output
        print("3. Writing output file...")
        let outputFileUrl = URL(fileURLWithPath: outputFileExapnded, relativeTo: cdUrl)
        
        FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)
        
        let outputFileHandle = try FileHandle(forWritingTo: outputFileUrl)
        
        for point in points {
            let pointBytes = point.serialize.data(using: .ascii)!
            outputFileHandle.write(pointBytes)
            outputFileHandle.write(newlineBytes)
        }
        outputFileHandle.closeFile()
        
        print("")
        print("Job complete")
    }
}

extension NumberFormatter {
    func string(fromDecimal: Decimal) -> String? {
        let ns = NSDecimalNumber(decimal: fromDecimal)
        return self.string(from: ns)
    }
}
