import CoreAudio

protocol AudioVolumeEngine: AnyObject {
    var gain: Float { get set }
    var processObjects: [AudioObjectID] { get }
    func stop()
}
