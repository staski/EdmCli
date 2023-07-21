//
//  main.swift
//  EdmCli
//
//  Created by Staszkiewicz, Carl Philipp on 22.02.22.
//

import Foundation
import ArgumentParser
import EdmParser

enum EdmCliError : Error {
    case invalidFlightId
}
struct EdmCli : ParsableCommand {
    
    enum VerbosityLevel : Int, CaseIterable {
        case quiet
        case standard
        case verbose
    }
    
    enum FuelUnit : String, ExpressibleByArgument {
            case lph, gph
    }
    
    @Argument(help: "EDM data file") var path: String
    @Option(name: [.customShort("i"),.customLong("id"), .customLong("flighId")], help: "The flight id") var flightId : Int?
    @Option(name: [.customShort("v"),.customLong("verbosity")], help: "verbosity level") var verbose : Int?
    @Option(name: [.customShort("u"),.customLong("fuelunit"), .customLong("fu")], help: "fuel unit [lph | gph]") var fuelunit : FuelUnit?
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
            if edmFileHeader.flightInfos[i].sizeBytes > 0 {
                edmFileParser.parseFlightHeaderAndBody(for: id)
            } else {
                print("main: flight id \(edmFileHeader.flightInfos[i].id) no data available")
            }
            
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
            do {
                if  short == true {
                    try printFlightSummary(fp: edmFileParser, flightId: flightId!, ffUnit: fuelunit)
                } else if long == true {
                    try printFlightInformationLong(fp: edmFileParser, flightId: flightId!, ffUnit: fuelunit)
                } else {
                    try printFlightInformation(fp: edmFileParser, flightId: flightId!, ffUnit: fuelunit)
                }
            } catch EdmCliError.invalidFlightId {
                print ("flight id \(flightId!) not found")
                try! printFileHeader(fp: edmFileParser)
            }
        }
     }

    func dumpFlight (for id : Int, fp: EdmFileParser) {
        let encoder = JSONEncoder()
        let formatter = DateFormatter()

        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        encoder.dateEncodingStrategy = .formatted(formatter)
        encoder.outputFormatting = .prettyPrinted

        guard let fd = fp.edmFileData.getFlight(for: id) else {
            trc(level: .error, string: "dumpFlight: no flight for id \(id)")
            return
        }
        
        do {
            let data = try encoder.encode(fd)
            let s = String(data: data, encoding: .utf8)
            print (s!)
        } catch {
            print ("error: \(error)")
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
        
        var ff_out_unit : FuelFlowUnit?
        switch fuelunit {
        case .lph:
            ff_out_unit = .LPH
        case .gph:
            ff_out_unit = .GPH
        default:
            ff_out_unit = fh.ff.getUnit()
        }
        
        print (fh.stringValue(includeFlights: false))
        for i in 0..<fp.edmFileData.edmFlightData.count {
            guard let h = fp.edmFileData.edmFlightData[i].flightHeader else {
                throw "invalid flight data at index \(i)"
            }
            
            var s = h.stringValue() + ", duration: " + fp.edmFileData.edmFlightData[i].duration.hms()
            let newUsed = String(format: "%6.1f  %@", fp.edmFileData.edmFlightData[i].getFuelUsed(outFuelUnit: ff_out_unit), ff_out_unit?.volumename ?? "")
            
            s.append(", fuel used: \(newUsed),")
            
            let recordCount = fp.edmFileData.edmFlightData[i].flightDataBody.count
            s.append(" \(recordCount) data records")
            print(s)
        }
    }
    
    func printFlightSummary (fp: EdmFileParser, flightId: Int, ffUnit : FuelUnit?) throws {
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
        
        var ff_out_unit : FuelFlowUnit?
        switch ffUnit {
        case .lph:
            ff_out_unit = .LPH
        case .gph:
            ff_out_unit = .GPH
        default:
            ff_out_unit = nil
        }
        
        guard fd != nil else {
            throw EdmCliError.invalidFlightId
            //throw ValidationError("no flight found with id \(flightId)")
        }
        
        guard let s = fd!.stringSummary(ff_out_unit: ff_out_unit) else {
            throw ValidationError("not able to extract string value")
        }
        
        print (s)
            
    }
    
    func printFlightInformation (fp: EdmFileParser, flightId: Int, ffUnit : FuelUnit?) throws {
        var fd : EdmFlightData?
        var start : Date = Date()
        //var max : Int = 0
        
        for f in fp.edmFileData.edmFlightData {
            guard let fh = f.flightHeader else {
                throw ValidationError("invalid header")
            }
            
            if fh.id == flightId {
                fd = f
                start = fh.date!
                //max = fh.alarmLimits.cht
                break
            }
        }
        
        var ff_out_unit : FuelFlowUnit?
        switch ffUnit {
        case .lph:
            ff_out_unit = .LPH
        case .gph:
            ff_out_unit = .GPH
        default:
            ff_out_unit = nil
        }
        
        guard fd != nil else {
            throw EdmCliError.invalidFlightId
            //throw ValidationError("no flight found with id \(flightId)")
        }
        
        guard var s = fd!.stringValue(ff_out_unit: ff_out_unit) else {
            throw ValidationError("not able to extract string value")
        }

        s.append("\n")

        guard let chtwarnintervals = fd!.getChtWarnIntervals() else {
            throw ValidationError("unable to retrieve cht warn intervals")
        }
        
        s = chtwarnintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("CHT warning above \(warn)F after " + d.hms() + " for \(duration) seconds \n")
        })

        guard let oillowintervals = fd!.getOilLowIntervals() else {
            throw ValidationError("unable to retrieve oil low warn intervals")
        }
        
        s = oillowintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Oil temperature below \(warn)°F after " + d.hms() + " for \(duration) seconds \n")
        })

        guard let oilhighintervals = fd!.getOilHighIntervals() else {
            throw ValidationError("unable to retrieve oil high warn intervals")
        }
        
        s = oilhighintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Oil temperature exceeded \(warn)°F after " + d.hms() + " for \(duration) seconds \n")
        })

        guard let coldwarnintervals = fd!.getColdWarnIntervals() else {
            throw ValidationError("unable to retrieve cold warn intervals")
        }
        
        s = coldwarnintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Cooling rate below \(warn)°F/min after " + d.hms() + " for \(duration) seconds \n")
        })
        
        guard let diffwarnintervals = fd!.getDiffWarnIntervals() else {
            throw ValidationError("unable to retrieve diff warn intervals")
        }
        
        s = diffwarnintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("EGT Spread above \(warn)°F after " + d.hms() + " for \(duration) seconds \n")
        })

        guard let oilhighwarn = fd!.getOilHighCount() else {
            throw ValidationError("unable to retrieve oil high warn count")
        }

        s = oilhighwarn.reduce(into: s, { (res, elem) in
            let (idx, oiltemp) = (elem.0, elem.1)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Oil temperature exceeded \(oiltemp)F after " + d.hms() + "\n")
        })
        
        let naintervals = fd!.getNAIntervals()

        for elem in naintervals {
            let str = elem.key
            for i in 0 ..< elem.value.count / 2 {
                let d1 = fd!.flightDataBody[elem.value[2*i]].date?.toString(dateFormat: "HH:mm") ?? "invalid"
                let d2 = fd!.flightDataBody[elem.value[2*i + 1]].date?.toString(dateFormat: "HH:mm") ?? "invalid"
                s.append("Sensor " + str + " not available: ")
                s.append(("from \(d1) to  \(d2)\n"))
            }
        }

        print (s)
    }

    func printFlightInformationLong (fp: EdmFileParser, flightId: Int, ffUnit : FuelUnit?) throws {
        var fd : EdmFlightData?
        var start : Date = Date()
        //var max : Int = 0
        
        for f in fp.edmFileData.edmFlightData {
            guard let fh = f.flightHeader else {
                throw ValidationError("invalid header")
            }
            
            if fh.id == flightId {
                fd = f
                start = fh.date!
                //max = fh.alarmLimits.cht
                break
            }
        }
        
        var ff_out_unit : FuelFlowUnit?
        switch ffUnit {
        case .lph:
            ff_out_unit = .LPH
        case .gph:
            ff_out_unit = .GPH
        default:
            ff_out_unit = nil
        }
        
        guard fd != nil else {
            throw EdmCliError.invalidFlightId
            //throw ValidationError("no flight found with id \(flightId)")
        }
        
        guard var s = fd!.stringValue(ff_out_unit: ff_out_unit) else {
            throw ValidationError("not able to extract string value")
        }

        s.append("\n")

        guard let fuelflowintervals = fd!.getFuelFlowIntervals() else {
            throw ValidationError("unable to retrieve fuel flow intervals")
        }
        
        s = fuelflowintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, value) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Fuel Flow \(value.stringValue()) after " + d.hms() + " for \(duration) seconds \n")
        })


        guard let chtwarnintervals = fd!.getChtWarnIntervals() else {
            throw ValidationError("unable to retrieve cht warn intervals")
        }
        
        s = chtwarnintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("CHT warning above \(warn)F after " + d.hms() + " for \(duration) seconds \n")
        })

        guard let oillowintervals = fd!.getOilLowIntervals() else {
            throw ValidationError("unable to retrieve oil low warn intervals")
        }
        
        s = oillowintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Oil temperature below \(warn)F after " + d.hms() + " for \(duration) seconds \n")
        })

        guard let oilhighintervals = fd!.getOilHighIntervals() else {
            throw ValidationError("unable to retrieve oil high warn intervals")
        }
        
        s = oilhighintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Oil temperature exceeded \(warn)F after " + d.hms() + " for \(duration) seconds \n")
        })

        guard let coldwarnintervals = fd!.getColdWarnIntervals() else {
            throw ValidationError("unable to retrieve cold warn intervals")
        }
        
        s = coldwarnintervals.reduce(into: s, { (res, elem) in
            let (idx, duration, warn) = (elem.0, elem.1, elem.2)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("COLD warning above \(warn)F after " + d.hms() + " for \(duration) seconds \n")
        })
        
        /*
        guard let cwarn = fd!.getChtWarnCount() else {
            throw ValidationError("unable to retrieve CHT warn count")
        }
        s.append("\n")
 
        s = cwarn.reduce(into: s){ res, elem in
            let (idx, cylCount) = (elem.0, elem.1)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            let d = t.timeIntervalSince(start)
            return res.append("CHT(\(idx)) of \(max)F exceeded on \(cylCount) cylinders after " + d.hms() + "\n")
        }

        guard let oillowwarn = fd!.getOilLowCount() else {
            throw ValidationError("unable to retrieve oil low warn count")
        }

        s = oillowwarn.reduce(into: s, { (res, elem) in
            let (idx, oiltemp) = (elem.0, elem.1)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Oil temperature low \(oiltemp)F after " + d.hms() + "\n")
        })
         */
        
        guard let oilhighwarn = fd!.getOilHighCount() else {
            throw ValidationError("unable to retrieve oil high warn count")
        }

        s = oilhighwarn.reduce(into: s, { (res, elem) in
            let (idx, oiltemp) = (elem.0, elem.1)
            let fr = fd!.flightDataBody[idx]
            guard let t = fr.date else {
                trc(level: .error, string: "FlightDataRecord.stringValue(): no date set")
                return
            }
            
            let d = t.timeIntervalSince(start)
            return res.append("Oil temperature exceeded \(oiltemp)F after " + d.hms() + "\n")
        })
        
        print (s)
    }
}

extension String : Error {}

EdmCli.main()

