//
//  main.swift
//  EdmCli
//
//  Created by Staszkiewicz, Carl Philipp on 22.02.22.
//

import Foundation
import ArgumentParser
import EdmParser

struct EdmCli : ParsableCommand {
    
    enum VerbosityLevel : Int, CaseIterable {
        case quiet
        case standard
        case verbose
    }
    
    @Argument(help: "EDM data file") var path: String
    @Option(name: [.customShort("i"),.customLong("id"), .customLong("flighId")], help: "The flight id") var flightId : Int?
    @Option(name: [.customShort("v"),.customLong("verbosity")], help: "verbosity level") var verbose : Int?
    @Flag(name: .shortAndLong, help: "print a summary only") var short = false
    @Flag(name: .shortAndLong, help: "print a summary only") var long = false
    
    func run() throws {
        let url = URL(fileURLWithPath: path)
        var edmFileParser : EdmFileParser
        
        if verbose == 1 {
            setTraceLevel(.warn)
        } else if verbose == 2 {
            setTraceLevel(.info)
        } else if verbose == 3 {
            setTraceLevel(.all)
        }
        
        
        guard let data = FileManager.default.contents(atPath: url.path) else {
            print (" open file: -- invalid data --- ")
            return
        }
        
        edmFileParser = EdmFileParser(data: data)

        guard let edmFileHeader = edmFileParser.parseFileHeaders() else {
            print ("invalid header")
            return
        }

        edmFileParser.edmFileData.edmFileHeader = edmFileHeader
        //var start : Date
        for i in 0..<edmFileHeader.flightInfos.count
        {
            if edmFileParser.complete == true {
                return
            }
            if edmFileParser.invalid == true {
                return
            }
            
            let id = edmFileHeader.flightInfos[i].id
            //start = Date()
            edmFileParser.parseFlightHeaderAndBody(for: id)
            /*
            let duration = Int(Date().timeIntervalSince(start) * 1000)
            print ("parse flight id \(id) took \(duration) milliseconds")
            */
        }

        if (flightId == nil) {
            if (long == false) {
                    try! printFileHeader(fp: edmFileParser)
            } else {
                dumpAll(fp: edmFileParser)
            }
        }
        else {
            try! printFlightSummary(fp: edmFileParser, flightId: flightId!)
        }
     }
    
    func dumpAll (fp: EdmFileParser) {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()

        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        encoder.dateEncodingStrategy = .formatted(formatter)
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(fp.edmFileData)
            let s = String(data: data, encoding: .utf8)
            print (s!)
        } catch {
            print ("error: \(error)")
        }
    }
    
    func printFileHeader(fp: EdmFileParser) throws {
        guard let fh = fp.edmFileData.edmFileHeader else {
            throw ValidationError("invalid header file")
        }
        print (fh.stringValue(includeFlights: true))
    }
    
    func printFlightSummary (fp: EdmFileParser, flightId: Int) throws {
        var fd : EdmFlightData?
        
        for f in fp.edmFileData.edmFlightData {
            guard let fh = f.flightHeader else {
                throw ValidationError("invalid header")
            }
            
            if fh.id == flightId {
                fd = f
                break
            }
        }
        
        guard fd != nil else {
            throw ValidationError("no flight found with id \(flightId)")
        }
        
        guard let s = fd!.stringValue() else {
            throw ValidationError("not able to extract string value")
        }
        
        print (s)
            
    }
}

EdmCli.main()

