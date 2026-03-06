//
//  OCRManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//

import Foundation
import Vision
import AppKit

/// OCRManager provides text recognition from screenshots using Apple's Vision framework
final class OCRManager {
    
    static let shared = OCRManager()
    
    private init() {}
    
    // MARK: - Text Recognition
    
    /// Extracts text from a CGImage using Vision framework OCR
    /// - Parameters:
    ///   - image: The image to extract text from
    ///   - completion: Callback with recognized text or error
    func recognizeText(from image: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        // Create Vision request
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                DispatchQueue.main.async {
                    completion(.success(""))
                }
                return
            }
            
            // Extract text from observations
            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
            
            DispatchQueue.main.async {
                completion(.success(recognizedText))
            }
        }
        
        // Configure for accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        // Detect language automatically based on system
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        
        // Perform recognition on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Synchronous version for simpler use cases
    func recognizeTextSync(from image: CGImage) -> String? {
        var result: String?
        let semaphore = DispatchSemaphore(value: 0)
        
        recognizeText(from: image) { textResult in
            if case .success(let text) = textResult {
                result = text
            }
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 10)
        return result
    }
    
    // MARK: - Copy Text Action
    
    /// Recognizes text from image and copies to clipboard
    func copyTextToClipboard(from image: CGImage, completion: @escaping (Bool, String?) -> Void) {
        recognizeText(from: image) { result in
            switch result {
            case .success(let text):
                if text.isEmpty {
                    completion(false, nil)
                } else {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    completion(true, text)
                }
            case .failure:
                completion(false, nil)
            }
        }
    }
}
