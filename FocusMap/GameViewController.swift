//
//  GameViewController.swift
//  FocusMap
//
//  Created by Hieu on 5/12/25.
//
// MARK: - Overview
// This file contains the main game view controller and UI components for FocusMap.
// It manages a 3D SceneKit scene with interactive planes, image textures, system icons,
// and camera controls. Users can tap planes to apply textures, move icons on the wall,
// and delete icons using directional controls.

import UIKit
import SceneKit

// MARK: - SCNVector3 Extension

/// Extension providing vector utility methods for 3D calculations in SceneKit
extension SCNVector3 {
    
    /// Calculates the Euclidean distance between this vector and another vector
    /// - Parameter vector: The target vector to calculate distance to
    /// - Returns: The distance as a Float value
    func distance(to vector: SCNVector3) -> Float {
        let dx = self.x - vector.x
        let dy = self.y - vector.y
        let dz = self.z - vector.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    /// Returns a normalized version of this vector (magnitude = 1)
    /// Used for maintaining camera direction during zoom operations
    /// - Returns: A new SCNVector3 with magnitude 1 in the same direction
    func normalized() -> SCNVector3 {
        let length = sqrt(x*x + y*y + z*z)
        guard length > 0 else { return SCNVector3(0, 0, 0) }
        return SCNVector3(x/length, y/length, z/length)
    }
}

// MARK: - GameViewController

/// Main view controller managing the 3D SceneKit view and user interactions
///
/// Responsibilities:
/// - Creates and manages the 3D scene with cuboid walls
/// - Handles tap gestures to select planes and display modal for texture selection
/// - Manages pinch gestures for camera zoom in/out
/// - Controls a movable system icon on the back wall with directional buttons
/// - Persists plane-to-image mappings to UserDefaults
/// - Manages movement button visibility and animation
///
class GameViewController: UIViewController {
    
    // MARK: - Properties
    
    // Scene and Camera
    
    /// Reference to the SceneKit view displaying the 3D scene
    var sceneView: SCNView?
    
    /// Reference to the camera node for zoom and navigation
    var cameraNode: SCNNode?
    
    /// Minimum zoom distance constraint (closest camera can get to scene)
    let minZoomDistance: Float = 2.0
    
    /// Maximum zoom distance constraint (farthest camera can be from scene)
    let maxZoomDistance: Float = 20.0
    
    // Plane and Image Management
    
    /// Currently selected plane node from user tap interaction
    var selectedPlaneNode: SCNNode?
    
    /// Dictionary mapping plane names to their assigned image texture names
    /// Format: ["bottomPlane": "wall1", "backPlane": "wall2", "leftPlane": "wall3", ...]
    /// This allows persistence of texture assignments across app sessions
    var planeMappings: [String: String] = [:]
    
    /// UserDefaults key for persisting plane-to-image mappings to disk
    let planeMappingsKey = "planeMappings"
    
    // Icon Management
    
    /// Array of all icon nodes currently positioned on the back wall
    /// Each icon can be independently moved and deleted
    var iconNodes: [SCNNode] = []
    
    /// Currently selected/focused icon node for movement and deletion operations
    /// Only this icon responds to movement buttons and delete button
    var focusedIconNode: SCNNode?
    
    /// Minimum distance between icon centers to prevent overlapping
    /// Used when generating random positions for new icons
    let minIconSpacing: Float = 0.25 // Approximately 1 icon unit (0.3 * 0.3 icons)
    
    // Button Management
    
    /// Array of movement control buttons (up, down, left, right, delete)
    /// Stored to allow toggling visibility and cleanup
    var movementButtons: [UIButton] = []
    
    /// Whether movement buttons are currently visible to the user
    var buttonsVisible: Bool = false
    
    // MARK: - Lifecycle Methods
    
    /// Called when the view controller's view is loaded into memory
    /// Sets up the 3D scene, gestures, image mappings, icon, and controls
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // MARK: Restore persistent data
        // Load previously saved plane-to-image mappings from UserDefaults
        if let saved = UserDefaults.standard.dictionary(forKey: planeMappingsKey) as? [String: String] {
            planeMappings = saved
        }
        
        // MARK: Initialize SceneKit view
        // Create the SceneKit view with full screen coverage and responsive sizing
        let sceneView = SCNView(frame: self.view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.scene = createScene()
        sceneView.backgroundColor = UIColor.black
        sceneView.allowsCameraControl = false // Manual camera control via gestures for better UX
        
        // MARK: Add gesture recognizers
        // Tap gesture for selecting planes and toggling icon movement buttons
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        // Pinch gesture for camera zoom in/out functionality
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        sceneView.addGestureRecognizer(pinchGesture)
        
        // MARK: Setup references and view hierarchy
        self.sceneView = sceneView
        self.cameraNode = sceneView.scene?.rootNode.childNodes.first { $0.camera != nil }
        self.view.addSubview(sceneView)
        
        // MARK: Restore visual state
        // Apply any previously saved texture mappings to the planes
        applyMappedImages()
        
        // Setup movement controls (initially hidden until icon is tapped)
        setupMovementControls()
    }
    
    // MARK: - Gesture Handlers
    
    /// Handles tap gestures on the scene view
    /// - Tapping the icon toggles movement button visibility
    /// - Tapping a wall plane opens the image/icon picker modal
    /// - Parameter gesture: The tap gesture recognizer
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let sceneView = gesture.view as? SCNView else { return }
        let location = gesture.location(in: sceneView)
        
        // MARK: Perform hit test to find nodes at tap location
        let hitResults = sceneView.hitTest(location, options: [:])
        
        for result in hitResults {
            let tappedNode = result.node
            
            // MARK: Check if icon was tapped
            // If an icon is tapped, focus on it and toggle the movement button visibility
            if tappedNode.name == "iconNode" {
                focusedIconNode = tappedNode
                toggleMovementButtons()
                return
            }
            
            // MARK: Validate node has valid geometry
            // Ensure the node has geometry and materials before proceeding
            guard let geometry = tappedNode.geometry else { continue }
            let materials = geometry.materials
            guard !materials.isEmpty else { continue }
            
            // MARK: Check node visibility
            // Verify both node opacity and material transparency indicate visibility
            let nodeVisible = tappedNode.presentation.opacity > 0.0
            let hasVisibleMaterial = materials.contains { material in
                // Transparency range: 1.0 (opaque) to 0.0 (transparent)
                // Consider visible if transparency > 0 (not fully transparent)
                material.transparency > 0.0
            }
            guard nodeVisible && hasVisibleMaterial else { continue }
            
            // MARK: Handle plane selection
            // A valid plane was tapped - proceed with selection
            print("Tapped plane: \(tappedNode.name ?? "Unknown")")
            
            // Provide visual feedback
            highlightPlane(tappedNode)
            
            // Select the plane and show the image/icon picker modal
            selectedPlaneNode = tappedNode
            showImagePickerModal()
            break
        }
    }
    
    /// Plays a highlight animation on the specified plane node
    /// Animation dims the plane opacity briefly (0.7), then restores it (1.0)
    /// Provides visual feedback that the plane was successfully tapped
    /// - Parameter node: The plane node to highlight
    func highlightPlane(_ node: SCNNode) {
        let action = SCNAction.sequence([
            SCNAction.run { _ in
                node.opacity = 0.7 // Dim the plane
            },
            SCNAction.wait(duration: 0.1), // Brief pause
            SCNAction.run { _ in
                node.opacity = 1.0 // Restore original opacity
            }
        ])
        node.runAction(action)
    }
    
    /// Handles pinch gestures for camera zoom in/out functionality
    /// Maintains camera direction while adjusting distance to the origin
    /// Constrains zoom distance between minZoomDistance and maxZoomDistance
    /// - Parameter gesture: The pinch gesture recognizer
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let cameraNode = cameraNode else { return }
        
        // MARK: Calculate new distance
        // Get the pinch scale factor and compute new camera distance
        let scale = Float(gesture.scale)
        let currentDistance = cameraNode.position.distance(to: SCNVector3(0, -0.5, 0))
        let newDistance = currentDistance / scale
        
        // MARK: Constrain zoom distance
        // Ensure zoom distance stays within defined bounds for usability
        let clampedDistance = max(minZoomDistance, min(maxZoomDistance, newDistance))
        
        // MARK: Update camera position
        // Recalculate camera position while maintaining its direction vector
        // This keeps the camera pointing at the same scene location while zooming
        let direction = cameraNode.position.normalized()
        cameraNode.position = SCNVector3(
            direction.x * clampedDistance,
            direction.y * clampedDistance,
            direction.z * clampedDistance
        )
        
        // MARK: Reset gesture scale
        // Reset scale for next pinch calculation to prevent cumulative scaling
        gesture.scale = 1.0
    }
    
    // MARK: - Scene Setup
    
    /// Creates and configures the 3D SceneKit scene with a cuboid, camera, and lighting
    /// The scene consists of:
    /// - A cuboid room with three visible walls (back, left, bottom)
    /// - Each wall can have custom textures applied
    /// - Isometric camera positioned at (5, 2, 5)
    /// - Main omnidirectional light and ambient light for proper illumination
    /// - Returns: Configured SCNScene with all scene elements
    func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // MARK: Cuboid dimensions
        // Define the size of the 3D room
        let width: CGFloat = 4.0
        let height: CGFloat = 3.0
        let depth: CGFloat = 2.0
        
        // MARK: Material factory
        /// Creates a material with specified color
        /// - Parameters:
        ///   - color: Color for the material
        /// - Returns: SCNMaterial configured with the color and double-sided rendering
        func createMaterial(color: UIColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.isDoubleSided = true // Visible from both sides
            return material
        }
        
        // MARK: Calculate half-dimensions
        // Used for positioning planes relative to the center origin
        let half_width = width / 2.0
        let half_height = height / 2.0
        let half_depth = depth / 2.0
        
        // MARK: Back Plane
        // Blue plane at the back of the scene - primary wall for icons and effects
        let backPlane = SCNPlane(width: width, height: height)
        backPlane.materials = [createMaterial(color: UIColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1.0))]
        let backNode = SCNNode(geometry: backPlane)
        backNode.name = "backPlane"
        backNode.position = SCNVector3(0, 0, Float(-half_depth))
        scene.rootNode.addChildNode(backNode)
        
        // MARK: Left Plane
        // Yellow plane on the left side of the scene
        let leftPlane = SCNPlane(width: CGFloat(Float(depth)), height: CGFloat(Float(height)))
        leftPlane.materials = [createMaterial(color: UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0))]
        let leftNode = SCNNode(geometry: leftPlane)
        leftNode.name = "leftPlane"
        leftNode.position = SCNVector3(Float(-half_width), 0, 0)
        leftNode.eulerAngles = SCNVector3(0, Float.pi / 2, 0) // Rotate 90 degrees
        scene.rootNode.addChildNode(leftNode)
        
        // MARK: Bottom Plane
        // Cyan plane at the bottom of the scene
        let bottomPlane = SCNPlane(width: width, height: CGFloat(Float(depth)))
        bottomPlane.materials = [createMaterial(color: UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0))]
        let bottomNode = SCNNode(geometry: bottomPlane)
        bottomNode.name = "bottomPlane"
        bottomNode.position = SCNVector3(0, Float(-half_height), 0)
        bottomNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0) // Rotate 90 degrees
        scene.rootNode.addChildNode(bottomNode)
        
        // MARK: Camera Setup
        // Create and position the camera for an isometric-like view
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(5, 2, 5) // Isometric-like perspective
        cameraNode.look(at: SCNVector3(0, -0.5, 0)) // Focus slightly below origin
        scene.rootNode.addChildNode(cameraNode)
        
        // MARK: Lighting Setup
        
        // MARK: Main light
        // Omnidirectional light source for primary illumination
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(5, 5, 5) // Position above and to the side
        scene.rootNode.addChildNode(lightNode)
        
        // MARK: Ambient light
        // Fill light for shadowed areas to prevent complete darkness
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor(white: 0.4, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        return scene
    }
    
    // MARK: - Interface Orientation
    
    /// Returns supported interface orientations based on device type
    /// iPhone: All orientations except upside-down
    /// iPad: All orientations
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
    
    /// Hides the status bar for a more immersive 3D experience
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - Image and Icon Picker Modal
    
    /// Presents the picker modal as a bottom sheet
    /// The modal displays collection views for different selectable items:
    /// 1. Wall textures (15 available wall images)
    /// 2. System icons (68 available window images)
    /// Users can select wall textures to apply to the tapped plane
    /// or select icons to create new icons on the wall at valid positions
    func showImagePickerModal() {
        let imagePickerVC = ImagePickerModalViewController()
        imagePickerVC.delegate = self
        
        // MARK: Initialize collections (setupCollections will be called in viewDidLoad)
        // The modal will automatically configure based on game state
        
        // MARK: Configure bottom sheet presentation
        // Present as a half-sheet modal with grab handle (iOS 15+)
        if #available(iOS 15.0, *) {
            if let sheet = imagePickerVC.sheetPresentationController {
                sheet.detents = [.custom(resolver: { _ in 350 })] // Height to fit all collections
                sheet.prefersGrabberVisible = true // Show drag handle for user awareness
            }
        }
        
        present(imagePickerVC, animated: true)
    }
    
    /// Applies all saved image mappings to their corresponding plane nodes
    /// Called during initialization and when restoring from persistent storage
    /// This ensures textures are restored when the app is relaunched
    func applyMappedImages() {
        guard let scene = sceneView?.scene else { return }
        
        // MARK: Iterate through all plane nodes
        // Apply the mapped image to each plane that has a saved mapping
        for node in scene.rootNode.childNodes {
            if let planeName = node.name, let imageName = planeMappings[planeName] {
                applyImageToNode(node, imageName: imageName)
            }
        }
    }
    
    /// Applies a vector image to a plane node's material
    /// Updates the plane's texture with the specified image from Assets
    /// - Parameters:
    ///   - node: The plane node to texture
    ///   - imageName: The name of the image asset (PDF/SVG supported)
    func applyImageToNode(_ node: SCNNode, imageName: String) {
        // MARK: Load the vector image
        // Retrieve the image from Assets
        guard let image = UIImage(named: imageName) else { return }
        
        // MARK: Update the plane's material
        // Create a new material with the image and apply it to the plane
        if let geometry = node.geometry {
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.isDoubleSided = true // Visible from both sides
            geometry.materials = [material]
        }
    }
    
    // MARK: - Icon on Wall Management
    
    /// Adds a new system image icon to the back wall at the specified position
    /// Checks for overlaps with existing icons to prevent stacking
    /// If a valid position cannot be found, returns without adding icon
    /// - Parameters:
    ///   - position: Normalized position (0.0-1.0) on the wall
    ///   - iconName: Name of the SF Symbol to display
    func addIconToWall(at position: (x: Float, y: Float), with iconName: String) {
        guard let scene = sceneView?.scene else { return }
        
        // MARK: Check for overlap with existing icons
        // Prevent new icons from overlapping with existing ones
        if isPositionOccupied(position: position) {
            print("Position occupied, icon not added")
            return
        }
        
        // MARK: Create icon plane
        // Create a 2D plane to hold the system icon image
        let iconSize: CGFloat = 0.3
        let iconPlane = SCNPlane(width: iconSize, height: iconSize)
        
        // MARK: Create window image material
        // Load the window image from Assets and apply it to the plane's material
        if let windowImage = UIImage(named: iconName) {
            let material = SCNMaterial()
            material.diffuse.contents = windowImage
            material.isDoubleSided = true // Visible from both sides
            iconPlane.materials = [material]
        }
        
        // MARK: Create and position icon node
        let newIconNode = SCNNode(geometry: iconPlane)
        newIconNode.name = "iconNode"
        
        // Convert normalized position to world coordinates and set
        let wallWidth: Float = 4.0
        let wallHeight: Float = 3.0
        let wallZ: Float = -0.95
        let x = (position.x - 0.5) * wallWidth
        let y = (0.5 - position.y) * wallHeight
        newIconNode.position = SCNVector3(x, y, wallZ)
        
        // Add to scene and tracking array
        scene.rootNode.addChildNode(newIconNode)
        iconNodes.append(newIconNode)
        
        // Focus on the newly created icon
        focusedIconNode = newIconNode
    }
    
    /// Checks if a position on the wall is already occupied by an existing icon
    /// Calculates the distance between the proposed position and all existing icons
    /// Returns true if any existing icon is closer than minIconSpacing
    /// - Parameter position: Normalized position (0.0-1.0) to check
    /// - Returns: True if position is occupied, false if available
    func isPositionOccupied(position: (x: Float, y: Float)) -> Bool {
        for iconNode in iconNodes {
            // MARK: Calculate distance between positions
            // Get the icon's current position and convert to normalized coordinates
            let iconX = (iconNode.position.x / 4.0) + 0.5
            let iconY = 0.5 - (iconNode.position.y / 3.0)
            
            // MARK: Check if distance is less than minimum spacing
            let distance = sqrt(pow(position.x - iconX, 2) + pow(position.y - iconY, 2))
            if distance < minIconSpacing {
                return true
            }
        }
        return false
    }
    
    /// Generates a random position on the wall that doesn't overlap with existing icons
    /// Attempts up to 10 random positions before giving up
    /// - Returns: A valid position (0.0-1.0 normalized), or nil if no position found
    func generateValidIconPosition() -> (x: Float, y: Float)? {
        let maxAttempts = 10
        
        for _ in 0..<maxAttempts {
            // MARK: Generate random position with padding
            // Avoid edges (0.15-0.85 range) to keep icons visible
            let position = (
                x: Float.random(in: 0.15..<0.85),
                y: Float.random(in: 0.15..<0.85)
            )
            
            // MARK: Check if position is available
            if !isPositionOccupied(position: position) {
                return position
            }
        }
        
        return nil
    }
    
    /// Moves the focused icon in the specified direction with boundary checking
    /// Prevents the icon from moving beyond the wall edges
    /// Movement increment is 0.05 (5% of wall width/height)
    /// - Parameter direction: Direction to move ("up", "down", "left", "right")
    func moveIcon(_ direction: String) {
        guard let focusedIconNode = focusedIconNode else { return }
        
        let moveAmount: Float = 0.05 // Movement step (5% of wall)
        
        // MARK: Get current normalized position
        let currentX = (focusedIconNode.position.x / 4.0) + 0.5
        let currentY = 0.5 - (focusedIconNode.position.y / 3.0)
        
        var newX = currentX
        var newY = currentY
        
        // MARK: Update position based on direction
        // Apply movement with boundary constraints (10%-90% of wall)
        switch direction {
        case "up":
            newY = max(0.1, currentY - moveAmount)
        case "down":
            newY = min(0.9, currentY + moveAmount)
        case "left":
            newX = max(0.1, currentX - moveAmount)
        case "right":
            newX = min(0.9, currentX + moveAmount)
        default:
            return
        }
        
        // MARK: Update icon position in 3D space
        let wallWidth: Float = 4.0
        let wallHeight: Float = 3.0
        let wallZ: Float = -0.95
        let x = (newX - 0.5) * wallWidth
        let y = (0.5 - newY) * wallHeight
        
        focusedIconNode.position = SCNVector3(x, y, wallZ)
    }
    
    // MARK: - Movement Controls UI
    
    /// Sets up movement control buttons arranged in a D-pad cluster
    /// Buttons are initially hidden and show when the icon is tapped
    /// Layout: up/down/left/right for movement attached to edges of center button
    func setupMovementControls() {
        let buttonSize: CGFloat = 50 // Size of each button
        let distance: CGFloat = 50 // Distance from center to button center (buttonSize / 2, so buttons touch edges)
        let centerX: CGFloat = view.bounds.maxX - 100 // Position in bottom-right area
        let centerY: CGFloat = view.bounds.maxY - 150
        
        // MARK: Up button (top of D-pad)
        let upButton = createControlButton(title: "↑", action: #selector(upButtonTapped))
        upButton.frame = CGRect(x: centerX - buttonSize/2, y: centerY - distance - buttonSize/2, width: buttonSize, height: buttonSize)
        movementButtons.append(upButton)
        view.addSubview(upButton)
        
        // MARK: Down button (bottom of D-pad)
        let downButton = createControlButton(title: "↓", action: #selector(downButtonTapped))
        downButton.frame = CGRect(x: centerX - buttonSize/2, y: centerY + distance - buttonSize/2, width: buttonSize, height: buttonSize)
        movementButtons.append(downButton)
        view.addSubview(downButton)
        
        // MARK: Left button (left of D-pad)
        let leftButton = createControlButton(title: "←", action: #selector(leftButtonTapped))
        leftButton.frame = CGRect(x: centerX - distance - buttonSize/2, y: centerY - buttonSize/2, width: buttonSize, height: buttonSize)
        movementButtons.append(leftButton)
        view.addSubview(leftButton)
        
        // MARK: Right button (right of D-pad)
        let rightButton = createControlButton(title: "→", action: #selector(rightButtonTapped))
        rightButton.frame = CGRect(x: centerX + distance - buttonSize/2, y: centerY - buttonSize/2, width: buttonSize, height: buttonSize)
        movementButtons.append(rightButton)
        view.addSubview(rightButton)
        
        // MARK: Center button (center of D-pad) - prints log when tapped
        let centerButton = createControlButton(title: "●", action: #selector(centerButtonTapped))
        centerButton.frame = CGRect(x: centerX - buttonSize/2, y: centerY - buttonSize/2, width: buttonSize, height: buttonSize)
        movementButtons.append(centerButton)
        view.addSubview(centerButton)
        
        // MARK: Delete button (left side, separate from D-pad)
        let deleteButton = createControlButton(title: "−", action: #selector(deleteIconButtonTapped))
        deleteButton.frame = CGRect(x: centerX - 180 - buttonSize/2, y: centerY - buttonSize/2, width: buttonSize, height: buttonSize)
        movementButtons.append(deleteButton)
        view.addSubview(deleteButton)
        
        // MARK: Hide all buttons initially
        // Buttons appear only when the icon is tapped
        hideMovementButtons()
    }
    
    /// Shows the movement buttons with a fade-in animation
    /// Sets buttons to visible and animates their alpha from 0 to 1
    func showMovementButtons() {
        buttonsVisible = true
        for button in movementButtons {
            button.alpha = 0
            button.isHidden = false
            UIView.animate(withDuration: 0.2) {
                button.alpha = 1.0
            }
        }
    }
    
    /// Hides the movement buttons with a fade-out animation
    /// Animates alpha from 1 to 0, then sets isHidden to true
    func hideMovementButtons() {
        buttonsVisible = false
        for button in movementButtons {
            UIView.animate(withDuration: 0.2, animations: {
                button.alpha = 0
            }) { _ in
                button.isHidden = true
            }
        }
    }
    
    /// Toggles visibility of movement buttons
    /// Shows buttons if hidden, hides buttons if shown
    func toggleMovementButtons() {
        if buttonsVisible {
            hideMovementButtons()
        } else {
            showMovementButtons()
        }
    }
    
    /// Creates a styled control button with the specified title and action
    /// Buttons have a semi-transparent black background with white text
    /// - Parameters:
    ///   - title: Text/symbol to display on button
    ///   - action: Selector for button tap action (optional)
    /// - Returns: Configured UIButton ready to be added to the view hierarchy
    private func createControlButton(title: String, action: Selector?) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .bold)
        button.tintColor = .white // White text/symbols
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6) // Semi-transparent black
        button.layer.cornerRadius = 12.5 // Circular button (50 / 2 = 25 for old size, 12.5 for new 50pt size)
        if let action {
            button.addTarget(self, action: action, for: .touchUpInside)
        }
        return button
    }
    
    // MARK: - Button Action Handlers
    
    /// Handle up button tap - move icon up on the wall
    @objc func upButtonTapped() {
        moveIcon("up")
    }
    
    /// Handle down button tap - move icon down on the wall
    @objc func downButtonTapped() {
        moveIcon("down")
    }
    
    /// Handle left button tap - move icon left on the wall
    @objc func leftButtonTapped() {
        moveIcon("left")
    }
    
    /// Handle right button tap - move icon right on the wall
    @objc func rightButtonTapped() {
        moveIcon("right")
    }
    
    /// Handle center button tap - print log message
    @objc func centerButtonTapped() {
        print("Center button tapped")
    }
    
    /// Handle delete button tap - remove the focused icon from the wall
    @objc func deleteIconButtonTapped() {
        guard let focusedIconNode = focusedIconNode else { return }
        
        // MARK: Remove focused icon from scene
        focusedIconNode.removeFromParentNode()
        
        // MARK: Remove from tracking array
        iconNodes.removeAll { $0 == focusedIconNode }
        
        // MARK: Clear focus and hide buttons
        self.focusedIconNode = nil
        hideMovementButtons()
    }
}

// MARK: - Picker Collection Type Enum

/// Defines the different types of collections available in the picker modal
/// Controls behavior, naming, and selection handling for each collection type
enum PickerCollectionType {
    case wall
    case window
    // Future: case shapes, case colors, etc.
    
    /// Display name for the collection
    var title: String {
        switch self {
        case .wall: return "Walls"
        case .window: return "Windows"
        }
    }
    
    /// Unique identifier for the collection
    var id: String {
        switch self {
        case .wall: return "wall"
        case .window: return "window"
        }
    }
}

// MARK: - Picker Collection Model

/// Represents a single collection section in the picker modal
/// Configured by PickerCollectionType enum for type-safe behavior
struct PickerCollection {
    let type: PickerCollectionType // Enum-based type for type-safe routing
    let items: [String] // Asset names to display
    let cellType: UICollectionViewCell.Type // Cell class to use
    let cellIdentifier: String
    let selectedItem: String? // Currently selected item
    let onSelect: (String) -> Void // Callback when item is selected
    
    var id: String { type.id }
    var title: String { type.title }
}

// MARK: - Image Picker Modal Controller

/// Modal view controller for selecting collections (textures, icons, etc.)
///
/// Responsibilities:
/// - Displays multiple horizontal collection views for different selection types
/// - Supports flexible collection types and behaviors based on PickerCollection config
/// - Handles selection callbacks dynamically
class ImagePickerModalViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    
    // MARK: - Properties
    
    // Delegation
    
    /// Weak reference to parent GameViewController for delegating selections
    weak var delegate: GameViewController?
    
    // Collections Configuration
    
    /// Array of all picker collections to display
    var collections: [PickerCollection] = []
    
    // UI Components
    
    /// Stack view containing all collection views vertically
    private let stackView = UIStackView()
    
    /// Dictionary mapping collection IDs to their collection view instances
    private var collectionViewMap: [String: UICollectionView] = [:]
    
    // MARK: - Lifecycle Methods
    
    /// Called when the view controller's view is loaded into memory
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        setupCollections()
        setupUI()
    }
    
    // MARK: - Setup Methods
    
    /// Configures the collections based on current game state
    /// Should be called before setupUI()
    private func setupCollections() {
        // MARK: Wall collection
        let wallCollection = PickerCollection(
            type: .wall,
            items: (1...15).map { "wall\($0)" },
            cellType: ImagePickerCell.self,
            cellIdentifier: "imageCell",
            selectedItem: delegate?.selectedPlaneNode?.name.flatMap { delegate?.planeMappings[$0] },
            onSelect: handleSelection
        )
        
        // MARK: Window collection
        let windowCollection = PickerCollection(
            type: .window,
            items: (1...68).map { "window\($0)" },
            cellType: IconSelectorCell.self,
            cellIdentifier: "iconCell",
            selectedItem: nil,
            onSelect: handleSelection
        )
        
        collections = [wallCollection, windowCollection]
    }
    
    /// Builds the UI from the configured collections
    private func setupUI() {
        // MARK: Setup stack view
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.distribution = .fillEqually
        
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // MARK: Create and add collection views for each collection
        for collection in collections {
            let collectionView = createCollectionView(for: collection)
            collectionViewMap[collection.id] = collectionView
            stackView.addArrangedSubview(collectionView)
        }
    }
    
    /// Creates a configured collection view for the given PickerCollection
    /// - Parameter collection: The PickerCollection to create a view for
    /// - Returns: Configured UICollectionView
    private func createCollectionView(for collection: PickerCollection) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 120, height: 120)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .systemBackground
        collectionView.isScrollEnabled = true
        collectionView.register(collection.cellType, forCellWithReuseIdentifier: collection.cellIdentifier)
        
        // Tag the collection view with the collection ID for identification
        collectionView.tag = collections.firstIndex { $0.id == collection.id } ?? 0
        
        return collectionView
    }
    
    // MARK: - UICollectionViewDataSource
    
    /// Returns the number of items in the specified collection view
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let collection = getCollection(for: collectionView) else { return 0 }
        return collection.items.count
    }
    
    /// Configures and returns a cell for the collection view
    /// Defers to each collection's specific cell type
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let collection = getCollection(for: collectionView) else {
            return UICollectionViewCell()
        }
        
        let itemName = collection.items[indexPath.item]
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: collection.cellIdentifier,
            for: indexPath
        )
        
        // Configure the cell based on its type
        if let pickerCell = cell as? ImagePickerCell {
            pickerCell.configure(with: itemName, isSelected: itemName == collection.selectedItem)
        } else if let iconCell = cell as? IconSelectorCell {
            iconCell.configure(with: itemName, isSelected: itemName == collection.selectedItem)
        }
        
        return cell
    }
    
    // MARK: - UICollectionViewDelegate
    
    /// Handles selection from any collection view
    /// Delegates to the appropriate handler based on collection type
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let collection = getCollection(for: collectionView) else { return }
        
        let selectedItem = collection.items[indexPath.item]
        collection.onSelect(selectedItem)
    }
    
    // MARK: - Helper Methods
    
    /// Retrieves the PickerCollection for a given UICollectionView
    /// - Parameter collectionView: The collection view to match
    /// - Returns: The matching PickerCollection, or nil if not found
    private func getCollection(for collectionView: UICollectionView) -> PickerCollection? {
        let tag = collectionView.tag
        guard tag < collections.count else { return nil }
        return collections[tag]
    }
    
    /// Unified handler for item selection across all collection types
    /// Routes to appropriate behavior based on collection type
    /// - Parameter selectedItem: The selected item name
    /// 
    /// Note: This closure is created with knowledge of which collection is calling it
    /// via the PickerCollection.onSelect callback
    private func handleSelection(_ selectedItem: String) {
        // Find which collection this selection came from
        guard let collection = collections.first(where: { $0.items.contains(selectedItem) }) else {
            dismiss(animated: true)
            return
        }
        
        // MARK: Route to appropriate handler based on collection type
        switch collection.type {
        case .wall:
            handleWallSelection(selectedItem)
        case .window:
            handleWindowSelection(selectedItem)
        }
    }
    
    /// Handles wall texture selection
    /// - Parameter wallName: The selected wall texture asset name
    private func handleWallSelection(_ wallName: String) {
        // MARK: Ensure a plane is selected
        guard let planeName = delegate?.selectedPlaneNode?.name else {
            dismiss(animated: true)
            return
        }
        
        // MARK: Update plane-to-image mapping
        delegate?.planeMappings[planeName] = wallName
        
        // MARK: Persist mapping to UserDefaults
        UserDefaults.standard.set(
            delegate?.planeMappings,
            forKey: delegate?.planeMappingsKey ?? "planeMappings"
        )
        
        // MARK: Apply image to plane
        delegate?.applyImageToNode(delegate!.selectedPlaneNode!, imageName: wallName)
        
        // MARK: Close the modal
        dismiss(animated: true)
    }
    
    /// Handles window icon selection
    /// - Parameter windowName: The selected window icon asset name
    private func handleWindowSelection(_ windowName: String) {
        // MARK: Generate valid position for new icon
        if let validPosition = delegate?.generateValidIconPosition() {
            // MARK: Create new icon at valid position
            delegate?.addIconToWall(at: validPosition, with: windowName)
        } else {
            // MARK: No valid position found - warn user
            print("No valid position found for new icon - wall may be full")
        }
        
        // MARK: Close the modal
        dismiss(animated: true)
    }
}

// MARK: - Image Picker Cell

/// Custom collection view cell for displaying selectable wall texture images
///
/// Visual features:
/// - Displays a thumbnail of the texture image
/// - Shows a blue border selection indicator when selected
/// - Uses padding and corner radius for polished appearance
///
class ImagePickerCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    /// Image view for displaying the texture thumbnail
    private let imageView = UIImageView()
    
    /// Visual indicator (blue border) shown when the cell is selected
    private let selectionIndicator = UIView()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup Methods
    
    /// Configures the cell's UI elements and Auto Layout constraints
    private func setupUI() {
        // MARK: Add subviews
        contentView.addSubview(imageView)
        contentView.addSubview(selectionIndicator)
        
        // MARK: Configure image view
        imageView.contentMode = .scaleAspectFill // Fill the cell while maintaining aspect ratio
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .systemGray6 // Placeholder background color
        
        // MARK: Configure selection indicator
        selectionIndicator.layer.borderColor = UIColor.systemBlue.cgColor
        selectionIndicator.layer.borderWidth = 3 // Visible blue border
        selectionIndicator.layer.cornerRadius = 8
        selectionIndicator.isHidden = true // Hidden until selected
        
        // MARK: Enable Auto Layout
        imageView.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // MARK: Apply constraints
        NSLayoutConstraint.activate([
            // Image view with padding from content view
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            // Selection indicator overlays the image
            selectionIndicator.topAnchor.constraint(equalTo: imageView.topAnchor),
            selectionIndicator.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            selectionIndicator.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            selectionIndicator.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
    }
    
    // MARK: - Configuration
    
    /// Configures the cell with an image and selection state
    /// - Parameters:
    ///   - imageName: Name of the image asset to display
    ///   - isSelected: Whether the cell is currently selected
    func configure(with imageName: String, isSelected: Bool) {
        imageView.image = UIImage(named: imageName)
        selectionIndicator.isHidden = !isSelected
    }
}

// MARK: - Icon Selector Cell

/// Custom collection view cell for displaying selectable window images
///
/// Visual features:
/// - Displays a window image from Assets
/// - Shows a blue border selection indicator when selected
/// - Uses aspect fill to show the image
/// - Matches the visual style of ImagePickerCell
///
class IconSelectorCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    /// Image view for displaying the window image
    private let iconView = UIImageView()
    
    /// Visual indicator (blue border) shown when the cell is selected
    private let selectionIndicator = UIView()
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup Methods
    
    /// Configures the cell's UI elements and Auto Layout constraints
    private func setupUI() {
        // MARK: Add subviews
        contentView.addSubview(iconView)
        contentView.addSubview(selectionIndicator)
        
        // MARK: Configure icon view
        iconView.contentMode = .scaleAspectFill // Fill the cell while maintaining aspect ratio
        iconView.clipsToBounds = true
        iconView.backgroundColor = .systemGray6 // Background color
        iconView.layer.cornerRadius = 8
        
        // MARK: Configure selection indicator
        selectionIndicator.layer.borderColor = UIColor.systemBlue.cgColor
        selectionIndicator.layer.borderWidth = 3
        selectionIndicator.layer.cornerRadius = 8
        selectionIndicator.isHidden = true // Hidden until selected
        
        // MARK: Enable Auto Layout
        iconView.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // MARK: Apply constraints
        NSLayoutConstraint.activate([
            // Icon view with padding from content view
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            iconView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            iconView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            
            // Selection indicator overlays the icon
            selectionIndicator.topAnchor.constraint(equalTo: iconView.topAnchor),
            selectionIndicator.leadingAnchor.constraint(equalTo: iconView.leadingAnchor),
            selectionIndicator.trailingAnchor.constraint(equalTo: iconView.trailingAnchor),
            selectionIndicator.bottomAnchor.constraint(equalTo: iconView.bottomAnchor)
        ])
    }
    
    // MARK: - Configuration
    
    /// Configures the cell with a window image and selection state
    /// - Parameters:
    ///   - iconName: Name of the window image asset to display
    ///   - isSelected: Whether the cell is currently selected
    func configure(with iconName: String, isSelected: Bool) {
        iconView.image = UIImage(named: iconName)
        selectionIndicator.isHidden = !isSelected
    }
}

