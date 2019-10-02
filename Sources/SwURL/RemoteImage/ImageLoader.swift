//
//  File 2.swift
//  
//
//  Created by Callum Trounce on 05/06/2019.
//

import Foundation
import CoreGraphics
import CoreImage
import Combine

public enum ImageLoadError: Error {
    case loaderDeallocated
    case malformedResponse
    case invalidImageData
    case cacheError
    case imageNotFound
    case generic(underlying: Error)
}


class ImageLoader {
    public typealias ImageLoadPromise = AnyPublisher<RemoteImageStatus, ImageLoadError>
    
    static let shared = ImageLoader()
    
    private let fileManager = FileManager()
    
    var cache: ImageCacheType = InMemoryImageCache()
    
    private let downloader = Downloader()
    
    public func load(url: URL) -> ImageLoadPromise {
        return retrieve(url: url)
    }
}


private extension ImageLoader {
    
    /// Retrieves image from URL
    /// - Parameter url: url at which you require the image.
    func retrieve(url: URL) -> ImageLoadPromise {
		let asyncLoad = downloader.download(from: url)
            .mapError(ImageLoadError.generic)
            .flatMap(handleDownload)
			.eraseToAnyPublisher()
		
		return cache.image(for: url)
			.map { cgImage in
				return RemoteImageStatus.complete(result: cgImage)
		}
		.catch { error -> ImageLoadPromise in
			return asyncLoad
		}.eraseToAnyPublisher()
	}
	
	/// Handles response of successful download response
    /// - Parameter response: data response from request
    /// - Parameter location: the url fthat was in the request.
    func handleDownload(downloadInfo: DownloadInfo) -> ImageLoadPromise {
        return Future<RemoteImageStatus, ImageLoadError>.init { [weak self] seal in
            guard let self = self else {
                seal(.failure(.loaderDeallocated))
                return
            }
            
			let url = downloadInfo.url
			guard let location = downloadInfo.resultURL else {
				SwURLDebug.log(
					level: .info,
					message: "Result url not present in handleDownload."
				)
                return
            }
            
            do {
                let directory = try self.fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent(location.lastPathComponent)
                try self.fileManager.copyItem(at: location, to: directory)
                
                guard
                    let imageSource = CGImageSourceCreateWithURL(directory as NSURL, nil) else {
                        seal(.failure(.cacheError))
                        return
                }
                
                guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
                    else {
                        seal(.failure(.cacheError))
                        return
                }
                
                self.cache.store(image: image, for: url)
				seal(.success(.complete(result: image)))
            } catch {
                seal(.failure(.generic(underlying: error)))
            }
        }.eraseToAnyPublisher()
    }
}
