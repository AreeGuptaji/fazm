//
//  Highlightr.swift
//  Pods
//
//  Created by Illanes, J.P. on 4/10/16.
//
//

import Foundation
import JavaScriptCore

#if os(OSX)
    import AppKit
#endif

/// Utility class for generating a highlighted NSAttributedString from a String.
open class Highlightr
{
    /// Returns the current Theme.
    open var theme : Theme!
    {
        didSet
        {
            themeChanged?(theme)
        }
    }
    
    /// This block will be called every time the theme changes.
    open var themeChanged : ((Theme) -> Void)?

    /// Defaults to `false` - when `true`, forces highlighting to finish even if illegal syntax is detected.
    open var ignoreIllegals = false

    private let hljs: JSValue

    private let bundle : Bundle
    private let htmlStart = "<"
    private let spanStart = "span class=\""
    private let spanStartClose = "\">"
    private let spanEnd = "/span>"
    private let htmlEscape = try! NSRegularExpression(pattern: "&#?[a-zA-Z0-9]+?;", options: .caseInsensitive)
    
    /**
     Default init method.

     - parameter highlightPath: The path to `highlight.min.js`. Defaults to `Highlightr.framework/highlight.min.js`

     - returns: Highlightr instance.
     */
    public init?(highlightPath: String? = nil)
    {
        guard let jsContext = JSContext() else { return nil }
        _ = JSValue(newObjectIn: jsContext)

        #if SWIFT_PACKAGE
        // SPM's auto-generated Bundle.module uses Bundle.main.bundleURL (the .app root)
        // to locate Highlightr_Highlightr.bundle — but on macOS the bundle is inside
        // Contents/Resources/. If Bundle.module can't find it there, it calls fatalError().
        //
        // Additionally, Bundle(path:) returns nil when the .bundle directory lacks an
        // Info.plist (SPM doesn't always generate one for processed resources).
        //
        // Strategy: try Bundle.main.resourceURL first, then Bundle.module, then
        // fall back to using the directory directly (wrapping it as a Bundle via URL).
        let bundleName = "Highlightr_Highlightr.bundle"
        let bundle: Bundle
        if let resourceURL = Foundation.Bundle.main.resourceURL?
            .appendingPathComponent(bundleName),
           let resourceBundle = Foundation.Bundle(path: resourceURL.path) {
            // Best case: proper bundle with Info.plist in Contents/Resources/
            bundle = resourceBundle
        } else if let resourceURL = Foundation.Bundle.main.resourceURL?
            .appendingPathComponent(bundleName),
           FileManager.default.fileExists(atPath:
               resourceURL.appendingPathComponent("highlight.min.js").path),
           let dirBundle = Foundation.Bundle(url: resourceURL) {
            // Bundle directory exists with resources but Bundle(path:) failed.
            // Try Bundle(url:) which can be more lenient with flat directories.
            bundle = dirBundle
        } else {
            // CLI tools, tests, or SwiftUI previews — use SPM's generated accessor.
            // Wrap in a check to avoid fatalError in production if paths are wrong.
            let spmMainPath = Foundation.Bundle.main.bundleURL
                .appendingPathComponent(bundleName).path
            if Foundation.Bundle(path: spmMainPath) != nil ||
               FileManager.default.fileExists(atPath: spmMainPath) {
                bundle = Bundle.module
            } else {
                return nil
            }
        }
        #else
        let bundle = Bundle(for: Highlightr.self)
        #endif
        self.bundle = bundle
        // If Bundle couldn't resolve resources (missing Info.plist), find the JS file
        // directly in the known resource directory.
        let hgPath: String
        if let path = highlightPath {
            hgPath = path
        } else if let path = bundle.path(forResource: "highlight.min", ofType: "js") {
            hgPath = path
        } else if let resourceURL = Foundation.Bundle.main.resourceURL?
            .appendingPathComponent(bundleName)
            .appendingPathComponent("highlight.min.js"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            // Direct file lookup — handles bundles without Info.plist where
            // Bundle.path(forResource:ofType:) returns nil.
            hgPath = resourceURL.path
        } else {
            return nil
        }
        
        guard let hgJs = try? String.init(contentsOfFile: hgPath) else { return nil }
        _ = jsContext.evaluateScript(hgJs)
        guard let hljs = jsContext.objectForKeyedSubscript("hljs") else { return nil }

        self.hljs = hljs
        
        guard setTheme(to: "pojoaque") else
        {
            return nil
        }
        
    }
    
    /**
     Set the theme to use for highlighting.
     
     - parameter to: Theme name
     
     - returns: true if it was possible to set the given theme, false otherwise
     */
    @discardableResult
    open func setTheme(to name: String) -> Bool
    {
        let defTheme: String
        if let path = bundle.path(forResource: name+".min", ofType: "css") {
            defTheme = path
        } else if let resourceURL = Foundation.Bundle.main.resourceURL?
            .appendingPathComponent("Highlightr_Highlightr.bundle")
            .appendingPathComponent(name + ".min.css"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            // Direct file lookup for bundles without Info.plist
            defTheme = resourceURL.path
        } else {
            return false
        }
        guard let themeString = try? String.init(contentsOfFile: defTheme) else { return false }
        theme =  Theme(themeString: themeString)

        
        return true
    }
    
    /**
     Takes a String and returns a NSAttributedString with the given language highlighted.
     
     - parameter code:           Code to highlight.
     - parameter languageName:   Language name or alias. Set to `nil` to use auto detection.
     - parameter fastRender:     Defaults to true - When *true* will use the custom made html parser rather than Apple's solution.
     
     - returns: NSAttributedString with the detected code highlighted.
     */
    open func highlight(_ code: String, as languageName: String? = nil, fastRender: Bool = true) -> NSAttributedString?
    {
        let ret: JSValue?
        if let languageName = languageName
        {
            let result: JSValue = hljs.invokeMethod("highlight", withArguments: [languageName, code, ignoreIllegals])
			 if result.isUndefined {
				// If highlighting failed, use highlightAuto
				ret = hljs.invokeMethod("highlightAuto", withArguments: [code])
			} else {
				ret = result
			}
        }else
        {
            // language auto detection
            ret = hljs.invokeMethod("highlightAuto", withArguments: [code])
        }

        guard let res = ret?.objectForKeyedSubscript("value"), var string = res.toString() else
        {
            return nil
        }
        
        var returnString : NSAttributedString?
        if(fastRender)
        {
            returnString = processHTMLString(string)
        }else
        {
            string = "<style>"+theme.lightTheme+"</style><pre><code class=\"hljs\">"+string+"</code></pre>"
            let opt: [NSAttributedString.DocumentReadingOptionKey : Any] = [
             .documentType: NSAttributedString.DocumentType.html,
             .characterEncoding: String.Encoding.utf8.rawValue
             ]
            
            guard let data = string.data(using: String.Encoding.utf8) else { return nil }
            safeMainSync
            {
                returnString = try? NSMutableAttributedString(data:data, options: opt, documentAttributes:nil)
            }
        }
        
        return returnString
    }
    
    /**
     Returns a list of all the available themes.
     
     - returns: Array of Strings
     */
    open func availableThemes() -> [String]
    {
        var paths = bundle.paths(forResourcesOfType: "css", inDirectory: nil) as [NSString]
        // Fallback: if Bundle API returns empty (missing Info.plist), scan directory directly
        if paths.isEmpty,
           let resourceURL = Foundation.Bundle.main.resourceURL?
            .appendingPathComponent("Highlightr_Highlightr.bundle"),
           let contents = try? FileManager.default.contentsOfDirectory(atPath: resourceURL.path) {
            paths = contents.filter { $0.hasSuffix(".css") }
                .map { resourceURL.appendingPathComponent($0).path as NSString }
        }
        var result = [String]()
        for path in paths {
            result.append(path.lastPathComponent.replacingOccurrences(of: ".min.css", with: ""))
        }

        return result
    }
    
    /**
     Returns a list of all supported languages.
     
     - returns: Array of Strings
     */
    open func supportedLanguages() -> [String]
    {
        let res = hljs.invokeMethod("listLanguages", withArguments: [])
        return (res?.toArray() as? [String]) ?? []
    }
    
    /**
     Execute the provided block in the main thread synchronously.
     */
    private func safeMainSync(_ block: @escaping ()->())
    {
        if Thread.isMainThread
        {
            block()
        }else
        {
            DispatchQueue.main.sync { block() }
        }
    }
    
    private func processHTMLString(_ string: String) -> NSAttributedString?
    {
        let scanner = Scanner(string: string)
        scanner.charactersToBeSkipped = nil
        var scannedString: NSString?
        let resultString = NSMutableAttributedString(string: "")
        var propStack = ["hljs"]
        
        while !scanner.isAtEnd
        {
            var ended = false
            if scanner.scanUpTo(htmlStart, into: &scannedString)
            {
                if scanner.isAtEnd
                {
                    ended = true
                }
            }
            
            if scannedString != nil && scannedString!.length > 0 {
                let attrScannedString = theme.applyStyleToString(scannedString! as String, styleList: propStack)
                resultString.append(attrScannedString)
                if ended
                {
                    continue
                }
            }
            
            scanner.scanLocation += 1
            
            let string = scanner.string as NSString
            let nextChar = string.substring(with: NSMakeRange(scanner.scanLocation, 1))
            if(nextChar == "s")
            {
                scanner.scanLocation += (spanStart as NSString).length
                scanner.scanUpTo(spanStartClose, into:&scannedString)
                scanner.scanLocation += (spanStartClose as NSString).length
                propStack.append(scannedString! as String)
            }
            else if(nextChar == "/")
            {
                scanner.scanLocation += (spanEnd as NSString).length
                propStack.removeLast()
            }else
            {
                let attrScannedString = theme.applyStyleToString("<", styleList: propStack)
                resultString.append(attrScannedString)
                scanner.scanLocation += 1
            }
            
            scannedString = nil
        }
        
        let results = htmlEscape.matches(in: resultString.string,
                                               options: [.reportCompletion],
                                               range: NSMakeRange(0, resultString.length))
        var locOffset = 0
        for result in results
        {
            let fixedRange = NSMakeRange(result.range.location-locOffset, result.range.length)
            let entity = (resultString.string as NSString).substring(with: fixedRange)
            if let decodedEntity = HTMLUtils.decode(entity)
            {
                resultString.replaceCharacters(in: fixedRange, with: String(decodedEntity))
                locOffset += result.range.length-1;
            }
            

        }

        return resultString
    }
    
}
