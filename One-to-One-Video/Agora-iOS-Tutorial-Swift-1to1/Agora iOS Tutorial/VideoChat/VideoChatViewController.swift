//
//  VideoChatViewController.swift
//  Agora iOS Tutorial
//
//  Created by James Fang on 7/14/16.
//  Copyright © 2016 Agora.io. All rights reserved.
//

import UIKit
import AgoraRtcEngineKit

@available(iOS 10.0, *)
class VideoChatViewController: UIViewController {
    @IBOutlet weak var localVideo: UIView!
    @IBOutlet weak var remoteVideo: UIView!
    @IBOutlet var overlayView: OverlayView!
    @IBOutlet var previewView: UIImageView!
    @IBOutlet weak var controlButtons: UIView!
    @IBOutlet weak var remoteVideoMutedIndicator: UIImageView!
    @IBOutlet weak var localVideoMutedBg: UIImageView!
    @IBOutlet weak var localVideoMutedIndicator: UIImageView!

    // MARK: Constants
    private let displayFont = UIFont.systemFont(ofSize: 14.0, weight: .medium)
    private let edgeOffset: CGFloat = 2.0
    private let labelOffset: CGFloat = 10.0
    private let animationDuration = 0.5
    private let collapseTransitionThreshold: CGFloat = -30.0
    private let expandThransitionThreshold: CGFloat = 30.0
    private let delayBetweenInferencesMs: Double = 200

    var agoraKit: AgoraRtcEngineKit!
    var agoraMediaDataPlugin: AgoraMediaDataPlugin?
    
    private let modelDataHandler: ModelDataHandler? = ModelDataHandler(modelFileName: "detect", labelsFileName: "labelmap", labelsFileExtension: "txt")

    // Holds the results at any time
    private var result: Result?
    private var previousInferenceTimeMs: TimeInterval = Date.distantPast.timeIntervalSince1970 * 1000

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        previewView = UIImageView()
        previewView.frame = view.frame
        view.addSubview(previewView)

        overlayView = OverlayView()
        overlayView.clearsContextBeforeDrawing = true
        overlayView.frame = view.frame
        overlayView.alpha = 0.5
        view.addSubview(overlayView)
        
        setupButtons()
        hideVideoMuted()
        initializeAgoraEngine()
        setupVideo()
        setupPlugIn()
        setupLocalVideo()
        joinChannel()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func initializeAgoraEngine() {
        agoraKit = AgoraRtcEngineKit.sharedEngine(withAppId: AppID, delegate: self)
    }

    func setupVideo() {
        agoraKit.setChannelProfile(.liveBroadcasting)
        agoraKit.enableVideo()  // Default mode is disableVideo
        agoraKit.setClientRole(.audience)
        agoraKit.setVideoEncoderConfiguration(AgoraVideoEncoderConfiguration(size: AgoraVideoDimension640x360,
                                                                             frameRate: .fps15,
                                                                             bitrate: AgoraVideoBitrateStandard,
                                                                             orientationMode: .adaptative))        
    }
    
    // MARK: for videodatamediapugin
    func setupPlugIn() {
        self.agoraMediaDataPlugin = AgoraMediaDataPlugin(agoraKit: agoraKit)
        self.agoraMediaDataPlugin?.videoDelegate = self
    }
    
    func setupLocalVideo() {
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = 0
        videoCanvas.view = localVideo
        videoCanvas.renderMode = .hidden
        agoraKit.setupLocalVideo(videoCanvas)
    }
    
    func joinChannel() {
        agoraKit.setDefaultAudioRouteToSpeakerphone(true)
        agoraKit.joinChannel(byToken: nil, channelId: "ar-core", info:nil, uid:2) {(sid, uid, elapsed) -> Void in
            // Did join channel "demoChannel1"
            print("Did join channel:", sid, uid)
        }
        
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    @IBAction func didClickHangUpButton(_ sender: UIButton) {
        leaveChannel()
    }
    
    func leaveChannel() {
        agoraKit.leaveChannel(nil)
        hideControlButtons()
        UIApplication.shared.isIdleTimerDisabled = false
        remoteVideo.removeFromSuperview()
        localVideo.removeFromSuperview()
    }
    
    func setupButtons() {
        perform(#selector(hideControlButtons), with:nil, afterDelay:8)
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(VideoChatViewController.ViewTapped))
        view.addGestureRecognizer(tapGestureRecognizer)
        view.isUserInteractionEnabled = true
    }

    @objc func hideControlButtons() {
        controlButtons.isHidden = true
    }
    
    @objc func ViewTapped() {
        if (controlButtons.isHidden) {
            controlButtons.isHidden = false;
            perform(#selector(hideControlButtons), with:nil, afterDelay:8)
        }
    }
    
    func resetHideButtonsTimer() {
        VideoChatViewController.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(hideControlButtons), with:nil, afterDelay:8)
    }
    
    @IBAction func didClickMuteButton(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        agoraKit.muteLocalAudioStream(sender.isSelected)
        resetHideButtonsTimer()
    }
    
    @IBAction func didClickVideoMuteButton(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        agoraKit.muteLocalVideoStream(sender.isSelected)
        localVideo.isHidden = sender.isSelected
        localVideoMutedBg.isHidden = !sender.isSelected
        localVideoMutedIndicator.isHidden = !sender.isSelected
        resetHideButtonsTimer()
    }
    
    func hideVideoMuted() {
        remoteVideoMutedIndicator.isHidden = true
        localVideoMutedBg.isHidden = true
        localVideoMutedIndicator.isHidden = true
    }
    
    @IBAction func didClickSwitchCameraButton(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
        agoraKit.switchCamera()
        resetHideButtonsTimer()
    }
}

@available(iOS 10.0, *)
extension VideoChatViewController: AgoraRtcEngineDelegate {
    func rtcEngine(_ engine: AgoraRtcEngineKit, firstRemoteVideoDecodedOfUid uid:UInt, size:CGSize, elapsed:Int) {
        if (remoteVideo.isHidden) {
            remoteVideo.isHidden = false
        }
        let videoCanvas = AgoraRtcVideoCanvas()
        videoCanvas.uid = uid
        videoCanvas.view = remoteVideo
        videoCanvas.renderMode = .hidden
        agoraKit.setupRemoteVideo(videoCanvas)
        agoraKit.setRemoteVideoRenderer(self, forUserId: uid)
    }
    
    internal func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid:UInt, reason:AgoraUserOfflineReason) {
        self.remoteVideo.isHidden = true
    }
    
    func rtcEngine(_ engine: AgoraRtcEngineKit, didVideoMuted muted:Bool, byUid:UInt) {
        remoteVideo.isHidden = muted
        remoteVideoMutedIndicator.isHidden = !muted
    }
}

@available(iOS 10.0, *)
extension VideoChatViewController: AgoraVideoDataPluginDelegate {
    
    func mediaDataPlugin(_ mediaDataPlugin: AgoraMediaDataPlugin!, didCapturedVideoRawData videoRawData: AgoraVideoRawData!) -> AgoraVideoRawData! {
        print("mediaDataPlugin.didCapturedVideoRawData")
        return videoRawData
    }
    
    func mediaDataPlugin(_ mediaDataPlugin: AgoraMediaDataPlugin!, willRenderVideoRawData videoRawData: AgoraVideoRawData!) -> AgoraVideoRawData! {
        print("mediaDataPlugin.willRenderVideoRawData")
        return videoRawData
    }
    
}

@available(iOS 10.0, *)
extension VideoChatViewController: AgoraVideoSinkProtocol {
    func shouldInitialize() -> Bool {
        return true
    }
    
    func shouldStart() {
    }
    
    func shouldStop() {
    }
    
    func shouldDispose() {
    }
    
    func bufferType() -> AgoraVideoBufferType {
        return .pixelBuffer
    }
    
    func pixelFormat() -> AgoraVideoPixelFormat {
        return .BGRA
    }

    func renderPixelBuffer(_ pixelBuffer: CVPixelBuffer, rotation: AgoraVideoRotation) {
        // Draws frame in preview view.
        let frame = CIImage(cvImageBuffer: pixelBuffer)
        DispatchQueue.main.async {
            self.previewView.image = UIImage(ciImage: frame)
            self.previewView.setNeedsDisplay()
        }

        self.runModel(onPixelBuffer: pixelBuffer)
    }
    
    func renderRawData(_ rawData: UnsafeMutableRawPointer, size: CGSize, rotation: AgoraVideoRotation) {
    }
}

@available(iOS 10.0, *)
extension VideoChatViewController {
    func runModel(onPixelBuffer pixelBuffer: CVPixelBuffer) {
        
        // Run the live camera pixelBuffer through tensorFlow to get the result
        
        let currentTimeMs = Date().timeIntervalSince1970 * 1000
        
        guard  (currentTimeMs - previousInferenceTimeMs) >= delayBetweenInferencesMs else {
            return
        }
        
        previousInferenceTimeMs = currentTimeMs
        result = self.modelDataHandler?.runModel(onFrame: pixelBuffer)
        
        
        guard let displayResult = result else {
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        DispatchQueue.main.async {
            
            // Display results by handing off to the InferenceViewController
//            self.inferenceViewController?.resolution = CGSize(width: width, height: height)
//
//            var inferenceTime: Double = 0
//            if let resultInferenceTime = self.result?.inferenceTime {
//                inferenceTime = resultInferenceTime
//            }
//            self.inferenceViewController?.inferenceTime = inferenceTime
//            self.inferenceViewController?.tableView.reloadData()


            // Draws the bounding boxes and displays class names and confidence scores.
            self.drawAfterPerformingCalculations(onInferences: displayResult.inferences, withImageSize: CGSize(width: CGFloat(width), height: CGFloat(height)))
        }
    }
    
    /**
     This method takes the results, translates the bounding box rects to the current view, draws the bounding boxes, classNames and confidence scores of inferences.
     */
     func drawAfterPerformingCalculations(onInferences inferences: [Inference], withImageSize imageSize:CGSize) {
        
        self.overlayView.objectOverlays = []
        self.overlayView.setNeedsDisplay()
        
        guard !inferences.isEmpty else {
            return
        }
        
        var objectOverlays: [ObjectOverlay] = []
        
        for inference in inferences {
            
            // Translates bounding box rect to current view.
            var convertedRect = inference.rect.applying(CGAffineTransform(scaleX: self.overlayView.bounds.size.width / imageSize.width, y: self.overlayView.bounds.size.height / imageSize.height))
            
            if convertedRect.origin.x < 0 {
                convertedRect.origin.x = self.edgeOffset
            }
            
            if convertedRect.origin.y < 0 {
                convertedRect.origin.y = self.edgeOffset
            }
            
            if convertedRect.maxY > self.overlayView.bounds.maxY {
                convertedRect.size.height = self.overlayView.bounds.maxY - convertedRect.origin.y - self.edgeOffset
            }
            
            if convertedRect.maxX > self.overlayView.bounds.maxX {
                convertedRect.size.width = self.overlayView.bounds.maxX - convertedRect.origin.x - self.edgeOffset
            }
            
            let confidenceValue = Int(inference.confidence * 100.0)
            let string = "\(inference.className)  (\(confidenceValue)%)"
            
            let size = string.size(usingFont: self.displayFont)
            
            let objectOverlay = ObjectOverlay(name: string, borderRect: convertedRect, nameStringSize: size, color: inference.displayColor, font: self.displayFont)
            
            objectOverlays.append(objectOverlay)
        }
        
        // Hands off drawing to the OverlayView
        self.draw(objectOverlays: objectOverlays)
        
    }
    
    /** Calls methods to update overlay view with detected bounding boxes and class names.
     */
    func draw(objectOverlays: [ObjectOverlay]) {
        
        self.overlayView.objectOverlays = objectOverlays
        self.overlayView.setNeedsDisplay()
    }

}
