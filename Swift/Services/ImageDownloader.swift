import Foundation
import UIKit


class ImageDownloader {
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func downloadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        if let cachedImage = cache.object(forKey: url.absoluteString as NSString) {
            completion(cachedImage)
            return
        }
        
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            guard
                let self = self,
                let data = data,
                let image = UIImage(data: data)
            else {
                completion(nil)
                return
            }
            
            self.cache.setObject(image, forKey: url.absoluteString as NSString)
            completion(image)
        }
        task.resume()
    }
}


extension UIImageView {
    func loadImage(from url: URL) {
        ImageDownloader().downloadImage(from: url) { [weak self] image in
            DispatchQueue.main.async {
                self?.image = image
            }
        }
    }
}


let imageView = UIImageView()
if let url = URL(string: "https://www.example.com/image.png") {
    imageView.loadImage(from: url)
}
