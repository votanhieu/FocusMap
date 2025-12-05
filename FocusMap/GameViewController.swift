//
//  GameViewController.swift
//  FocusMap
//
//  Created by Hieu on 5/12/25.
//

import UIKit
import SceneKit

class GameViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create SceneKit view
        let sceneView = SCNView(frame: self.view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.scene = createScene()
        sceneView.backgroundColor = UIColor.black
        sceneView.allowsCameraControl = false
        self.view.addSubview(sceneView)
    }
    
    func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Parameters
        let size: CGFloat = 4.0
        let half = size / 2.0
        
        // Helper materials: front vs back
        // Front is the side along the plane's normal; back is the opposite side.
        func twoSidedMaterials(front: UIColor, back: UIColor, doubleSided: Bool = true) -> [SCNMaterial] {
            let frontMat = SCNMaterial()
            frontMat.diffuse.contents = front
            frontMat.isDoubleSided = doubleSided
            
            let backMat = SCNMaterial()
            backMat.diffuse.contents = back
            backMat.isDoubleSided = doubleSided
            
            // For SCNPlane, first material is used for front faces, second for back faces
            return [frontMat, backMat]
        }
        
        // Bottom face (y = -half), plane normal pointing up (positive Y)
        let bottomPlane = SCNPlane(width: size, height: size)
        bottomPlane.materials = twoSidedMaterials(
            front: UIColor.systemGreen.withAlphaComponent(0.6),   // visible when seen from above
            back: UIColor.systemRed.withAlphaComponent(0.3)       // visible when seen from below
        )
        let bottomNode = SCNNode(geometry: bottomPlane)
        bottomNode.position = SCNVector3(0, Float(-half), 0)
        // Rotate plane (which by default faces +Z) to face +Y
        bottomNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(bottomNode)
        
        // Back face (z = -half), plane normal pointing forward (+Z)
        let backPlane = SCNPlane(width: size, height: size)
        backPlane.materials = twoSidedMaterials(
            front: UIColor.systemBlue.withAlphaComponent(0.6),    // visible when seen from in front (toward +Z)
            back: UIColor.systemOrange.withAlphaComponent(0.3)    // visible from behind
        )
        let backNode = SCNNode(geometry: backPlane)
        backNode.position = SCNVector3(0, 0, Float(-half))
        // Default plane faces +Z already; align Y-up
        backNode.eulerAngles = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(backNode)
        
        // Left face (x = -half), plane normal pointing +X
        let leftPlane = SCNPlane(width: size, height: size)
        leftPlane.materials = twoSidedMaterials(
            front: UIColor.systemYellow.withAlphaComponent(0.6),  // visible when seen from +X side
            back: UIColor.systemPurple.withAlphaComponent(0.3)    // visible from -X side
        )
        let leftNode = SCNNode(geometry: leftPlane)
        leftNode.position = SCNVector3(Float(-half), 0, 0)
        // Rotate to face +X: rotate -90° about Y (negative)
        leftNode.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        scene.rootNode.addChildNode(leftNode)
        
        // If you intended both back-side faces, also add right face (x = +half)
        // Uncomment the following block if you want both sides:
        /*
        let rightPlane = SCNPlane(width: size, height: size)
        rightPlane.materials = twoSidedMaterials(
            front: UIColor.systemTeal.withAlphaComponent(0.6),
            back: UIColor.systemPink.withAlphaComponent(0.3)
        )
        let rightNode = SCNNode(geometry: rightPlane)
        rightNode.position = SCNVector3(Float(half), 0, 0)
        // Rotate to face -X: rotate +90° about Y (positive)
        rightNode.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
        scene.rootNode.addChildNode(rightNode)
        */
        
        // Simple fixed camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(5, 4, 5)
        cameraNode.look(at: SCNVector3(0, -0.5, 0))
        scene.rootNode.addChildNode(cameraNode)
        
        // Add lighting
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(5, 5, 5)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor(white: 0.4, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        return scene
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
