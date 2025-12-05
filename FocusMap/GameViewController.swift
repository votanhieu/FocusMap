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
        sceneView.scene = createScene()
        sceneView.backgroundColor = UIColor.black
        sceneView.allowsCameraControl = false
        self.view.addSubview(sceneView)
    }
    
    func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Create a cube node
        let cube = SCNBox(width: 4, height: 4, length: 4, chamferRadius: 0)
        let cubeNode = SCNNode(geometry: cube)
        cubeNode.position = SCNVector3(0, 0, 0)
        
        // Create a semi-transparent material to see inside
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 0.3)
        material.specular.contents = UIColor.white
        material.transparency = 0.4
        material.isDoubleSided = true
        cube.materials = [material]
        
        scene.rootNode.addChildNode(cubeNode)
        
        // Add interior planes to visualize inside better
        addInteriorPlanes(to: scene)
        
        // Create camera with beautiful isometric view
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
        ambientLight.light!.color = UIColor.gray
        scene.rootNode.addChildNode(ambientLight)
        
        return scene
    }
    
    func addInteriorPlanes(to scene: SCNScene) {
        // Add grid lines on interior faces for better visualization
        let wireframe = createWireframeBox()
        scene.rootNode.addChildNode(wireframe)
    }
    
    func createWireframeBox() -> SCNNode {
        let group = SCNNode()
        
        let size: CGFloat = 4.0
        let offset = size / 2
        
        // Define 8 vertices of the cube
        let vertices: [SCNVector3] = [
            SCNVector3(-offset, -offset, -offset), // 0
            SCNVector3(offset, -offset, -offset),  // 1
            SCNVector3(offset, offset, -offset),   // 2
            SCNVector3(-offset, offset, -offset),  // 3
            SCNVector3(-offset, -offset, offset),  // 4
            SCNVector3(offset, -offset, offset),   // 5
            SCNVector3(offset, offset, offset),    // 6
            SCNVector3(-offset, offset, offset)    // 7
        ]
        
        // Define 12 edges (pairs of vertex indices)
        let edges: [(Int, Int)] = [
            // Front face
            (0, 1), (1, 2), (2, 3), (3, 0),
            // Back face
            (4, 5), (5, 6), (6, 7), (7, 4),
            // Connecting edges
            (0, 4), (1, 5), (2, 6), (3, 7)
        ]
        
        // Create lines for each edge
        for (startIdx, endIdx) in edges {
            let line = createLine(from: vertices[startIdx], to: vertices[endIdx])
            group.addChildNode(line)
        }
        
        return group
    }
    
    func createLine(from start: SCNVector3, to end: SCNVector3) -> SCNNode {
        let indices: [Int32] = [0, 1]
        let source = SCNGeometrySource(vertices: [start, end])
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.cyan
        geometry.materials = [material]
        
        return SCNNode(geometry: geometry)
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
