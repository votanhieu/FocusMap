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
    
    /// Node representing the system image icon positioned on the back wall
    var iconNode: SCNNode?
    
    /// Current position of the icon on the wall using normalized coordinates (0.0 to 1.0)
    /// Where (0.5, 0.5) is the center of the wall
    /// x: 0.0 (left edge) to 1.0 (right edge)
    /// y: 0.0 (bottom edge) to 1.0 (top edge)
    var iconPosition: (x: Float, y: Float) = (0.5, 0.5)
    
    /// Current system icon name selected for the wall icon (SF Symbols)
    /// Examples: "mappin.circle.fill", "star.fill", "heart.fill", etc.
    var currentIconName: String = "mappin.circle.fill"
    
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
        
        // Add the system icon to the back wall
        addIconToWall()
        
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
            // If the icon is tapped, toggle the movement button visibility
            if tappedNode.name == "iconNode" {
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
    
    /// Presents the image/icon picker modal as a bottom sheet
    /// The modal displays two collection views:
    /// 1. Wall textures (15 available wall images)
    /// 2. System icons (15 available SF Symbols)
    /// Users can select wall textures to apply to the tapped plane
    /// or select icons to create new icons on the wall at random positions
    func showImagePickerModal() {
        let imagePickerVC = ImagePickerModalViewController()
        imagePickerVC.delegate = self
        
        // MARK: Pass currently selected image
        // Pre-select the current texture applied to the tapped plane
        if let planeName = selectedPlaneNode?.name {
            imagePickerVC.selectedImageName = planeMappings[planeName]
        }
        
        // MARK: Configure bottom sheet presentation
        // Present as a half-sheet modal with grab handle (iOS 15+)
        if #available(iOS 15.0, *) {
            if let sheet = imagePickerVC.sheetPresentationController {
                sheet.detents = [.custom(resolver: { _ in 350 })] // Height to fit both collections
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
    
    /// Adds a system image icon positioned on the back wall
    /// The icon is rendered as a plane with the current system icon image
    /// Positioned based on the iconPosition coordinates
    func addIconToWall() {
        guard let scene = sceneView?.scene else { return }
        
        // MARK: Remove existing icon
        // Clean up the previous icon if one exists
        iconNode?.removeFromParentNode()
        
        // MARK: Create icon plane
        // Create a 2D plane to hold the system icon image
        let iconSize: CGFloat = 0.3
        let iconPlane = SCNPlane(width: iconSize, height: iconSize)
        
        // MARK: Create system image material
        // Load the system icon and apply it to the plane's material
        if let systemImage = UIImage(systemName: currentIconName) {
            let material = SCNMaterial()
            material.diffuse.contents = systemImage
            material.isDoubleSided = true // Visible from both sides
            iconPlane.materials = [material]
        }
        
        // MARK: Create and position icon node
        let newIconNode = SCNNode(geometry: iconPlane)
        newIconNode.name = "iconNode"
        
        // Position on back wall based on current position
        updateIconPosition()
        
        scene.rootNode.addChildNode(newIconNode)
        iconNode = newIconNode
    }
    
    /// Updates the wall icon with the current selected icon name
    /// Removes the old icon and creates a new one with the updated icon image
    /// Preserves the icon's position on the wall
    func updateWallIcon() {
        guard let scene = sceneView?.scene else { return }
        
        // MARK: Remove existing icon
        // Clean up the previous icon
        iconNode?.removeFromParentNode()
        
        // MARK: Create new icon plane
        // Create a new plane with the updated system image
        let iconSize: CGFloat = 0.3
        let iconPlane = SCNPlane(width: iconSize, height: iconSize)
        
        // MARK: Load new system image
        if let systemImage = UIImage(systemName: currentIconName) {
            let material = SCNMaterial()
            material.diffuse.contents = systemImage
            material.isDoubleSided = true
            iconPlane.materials = [material]
        }
        
        // MARK: Create and position new icon node
        let newIconNode = SCNNode(geometry: iconPlane)
        newIconNode.name = "iconNode"
        
        // Restore the previous position
        updateIconPosition()
        
        scene.rootNode.addChildNode(newIconNode)
        iconNode = newIconNode
    }
    
    /// Updates icon position on the wall based on iconPosition coordinates
    /// Converts normalized coordinates (0.0-1.0) to wall space coordinates
    /// Constrains position to stay within wall bounds with padding
    func updateIconPosition() {
        guard let iconNode = iconNode else { return }
        
        // MARK: Define wall bounds
        // Wall dimensions: width 4.0, height 3.0, positioned at z = -1.0
        let wallWidth: Float = 4.0
        let wallHeight: Float = 3.0
        let wallZ: Float = -0.95 // Slightly in front of back wall to prevent z-fighting
        
        // MARK: Convert normalized position to wall coordinates
        // Map (0.0-1.0) range to actual wall coordinates
        // X: left (-2.0) to right (2.0)
        // Y: bottom (-1.5) to top (1.5)
        let x = (iconPosition.x - 0.5) * wallWidth
        let y = (0.5 - iconPosition.y) * wallHeight // Flip Y for intuitive top-down mapping
        
        iconNode.position = SCNVector3(x, y, wallZ)
    }
    
    /// Moves the icon in the specified direction with boundary checking
    /// Prevents the icon from moving beyond the wall edges
    /// Movement increment is 0.05 (5% of wall width/height)
    /// - Parameter direction: Direction to move ("up", "down", "left", "right")
    func moveIcon(_ direction: String) {
        let moveAmount: Float = 0.05 // Movement step (5% of wall)
        
        // MARK: Update position based on direction
        // Apply movement with boundary constraints (10%-90% of wall)
        switch direction {
        case "up":
            iconPosition.y = max(0.1, iconPosition.y - moveAmount)
        case "down":
            iconPosition.y = min(0.9, iconPosition.y + moveAmount)
        case "left":
            iconPosition.x = max(0.1, iconPosition.x - moveAmount)
        case "right":
            iconPosition.x = min(0.9, iconPosition.x + moveAmount)
        default:
            return
        }
        
        // MARK: Update visual position
        updateIconPosition()
    }
    
    // MARK: - Movement Controls UI
    
    /// Sets up movement control buttons arranged in a D-pad cluster
    /// Buttons are initially hidden and show when the icon is tapped
    /// Layout: up/down/left/right for movement, delete button on the left
    func setupMovementControls() {
        let buttonSize: CGFloat = 80 // Size of each button
        let distance: CGFloat = 50 // Distance from center to button center
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
    ///   - action: Selector for button tap action
    /// - Returns: Configured UIButton ready to be added to the view hierarchy
    private func createControlButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .bold)
        button.tintColor = .white // White text/symbols
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6) // Semi-transparent black
        button.layer.cornerRadius = 25 // Circular button
        button.addTarget(self, action: action, for: .touchUpInside)
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
    
    /// Handle delete button tap - remove the icon from the wall
    @objc func deleteIconButtonTapped() {
        // MARK: Remove icon from scene
        iconNode?.removeFromParentNode()
        iconNode = nil
    }
}

// MARK: - Image Picker Modal Controller

/// Modal view controller for selecting wall textures and system icons
///
/// Responsibilities:
/// - Displays two horizontal collection views:
///   1. Wall texture images (15 wall texture options)
///   2. System icons (15 SF Symbols options)
/// - Handles texture selection and application to tapped plane
/// - Handles icon selection and creation at random position
/// - Persists plane-to-texture mappings
///
class ImagePickerModalViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    
    // MARK: - Properties
    
    // Delegation
    
    /// Weak reference to parent GameViewController for delegating selections
    weak var delegate: GameViewController?
    
    // Selection State
    
    /// Currently selected image name (for visual highlighting in wall collection)
    var selectedImageName: String?
    
    /// Currently selected icon name (for visual highlighting in icon collection)
    var selectedIconName: String?
    
    // Data Sources
    
    /// List of available wall texture image asset names
    /// Generates names like "wall1", "wall2", ..., "wall15"
    let imageNames = (1...15).map { "wall\($0)" }
    
    /// List of available system icon names (SF Symbols)
    /// Includes a diverse set of icons for various uses
    let iconNames = [
        "mappin.circle.fill",      // Location/map pin
        "star.fill",               // Star/favorite
        "heart.fill",              // Heart/love
        "sun.max.fill",            // Sun/light
        "moon.fill",               // Moon/night
        "cloud.fill",              // Cloud/weather
        "bolt.fill",               // Lightning/electricity
        "flame.fill",              // Fire/heat
        "snow",                    // Snow/cold
        "wind",                    // Wind/air
        "raincloud.fill",          // Rain/precipitation
        "checkmark.circle.fill",   // Check/complete
        "xmark.circle.fill",       // X/close
        "questionmark.circle.fill",// Question/help
        "exclamationmark.circle.fill" // Exclamation/alert
    ]
    
    // UI Components
    
    /// Collection view for displaying selectable wall texture thumbnails
    /// Scrolls horizontally with fixed height of 160pt
    private let imageCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    
    /// Collection view for displaying selectable system icons
    /// Scrolls horizontally with fixed height of 160pt
    private let iconCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    
    // MARK: - Lifecycle Methods
    
    /// Called when the view controller's view is loaded into memory
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        setupCollectionView()
    }
    
    // MARK: - Setup Methods
    
    /// Configures both collection views with layouts, delegates, and constraints
    /// Sets up the hierarchy: image collection on top, icon collection below
    private func setupCollectionView() {
        // MARK: Image collection view setup
        
        let imageLayout = UICollectionViewFlowLayout()
        imageLayout.scrollDirection = .horizontal
        imageLayout.itemSize = CGSize(width: 120, height: 120) // Square cells
        imageLayout.minimumInteritemSpacing = 16 // Space between items
        imageLayout.minimumLineSpacing = 0
        imageLayout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 12, right: 16) // Padding
        
        imageCollectionView.setCollectionViewLayout(imageLayout, animated: false)
        imageCollectionView.delegate = self
        imageCollectionView.dataSource = self
        imageCollectionView.showsHorizontalScrollIndicator = false
        imageCollectionView.showsVerticalScrollIndicator = false
        imageCollectionView.backgroundColor = .systemBackground
        imageCollectionView.isScrollEnabled = true
        imageCollectionView.register(ImagePickerCell.self, forCellWithReuseIdentifier: "imageCell")
        
        // MARK: Icon collection view setup
        
        let iconLayout = UICollectionViewFlowLayout()
        iconLayout.scrollDirection = .horizontal
        iconLayout.itemSize = CGSize(width: 120, height: 120)
        iconLayout.minimumInteritemSpacing = 16
        iconLayout.minimumLineSpacing = 0
        iconLayout.sectionInset = UIEdgeInsets(top: 12, left: 16, bottom: 8, right: 16)
        
        iconCollectionView.setCollectionViewLayout(iconLayout, animated: false)
        iconCollectionView.delegate = self
        iconCollectionView.dataSource = self
        iconCollectionView.showsHorizontalScrollIndicator = false
        iconCollectionView.showsVerticalScrollIndicator = false
        iconCollectionView.backgroundColor = .systemBackground
        iconCollectionView.isScrollEnabled = true
        iconCollectionView.register(IconSelectorCell.self, forCellWithReuseIdentifier: "iconCell")
        
        // MARK: Add to view hierarchy
        
        view.addSubview(imageCollectionView)
        view.addSubview(iconCollectionView)
        
        imageCollectionView.translatesAutoresizingMaskIntoConstraints = false
        iconCollectionView.translatesAutoresizingMaskIntoConstraints = false
        
        // MARK: Apply constraints
        
        NSLayoutConstraint.activate([
            // Image collection: top of modal to fixed height
            imageCollectionView.topAnchor.constraint(equalTo: view.topAnchor),
            imageCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageCollectionView.heightAnchor.constraint(equalToConstant: 160),
            
            // Icon collection: below image collection to fixed height
            iconCollectionView.topAnchor.constraint(equalTo: imageCollectionView.bottomAnchor),
            iconCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            iconCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            iconCollectionView.heightAnchor.constraint(equalToConstant: 160)
        ])
    }
    
    // MARK: - UICollectionViewDataSource
    
    /// Returns the number of items in the specified collection view
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == imageCollectionView {
            return imageNames.count
        } else {
            return iconNames.count
        }
    }
    
    /// Configures and returns a cell for the collection view
    /// Uses different cell types and identifiers for images vs icons
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView == imageCollectionView {
            // MARK: Image cell configuration
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "imageCell", for: indexPath) as! ImagePickerCell
            
            let imageName = imageNames[indexPath.item]
            let isSelected = imageName == selectedImageName
            cell.configure(with: imageName, isSelected: isSelected)
            
            return cell
        } else {
            // MARK: Icon cell configuration
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "iconCell", for: indexPath) as! IconSelectorCell
            
            let iconName = iconNames[indexPath.item]
            let isSelected = iconName == selectedIconName
            cell.configure(with: iconName, isSelected: isSelected)
            
            return cell
        }
    }
    
    // MARK: - UICollectionViewDelegate
    
    /// Handles selection from either collection view
    /// Applies texture to plane if image selected, creates new icon if icon selected
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView == imageCollectionView {
            // MARK: Handle wall texture selection
            
            let selectedImageName = imageNames[indexPath.item]
            
            // MARK: Ensure a plane is selected
            // If no plane was selected, just close the modal
            guard let planeName = delegate?.selectedPlaneNode?.name else {
                dismiss(animated: true)
                return
            }
            
            // MARK: Update plane-to-image mapping
            // Store the mapping in memory
            delegate?.planeMappings[planeName] = selectedImageName
            
            // MARK: Persist mapping to UserDefaults
            // Save for future app sessions
            UserDefaults.standard.set(
                delegate?.planeMappings,
                forKey: delegate?.planeMappingsKey ?? "planeMappings"
            )
            
            // MARK: Apply image to plane
            // Update the visual appearance of the plane
            delegate?.applyImageToNode(delegate!.selectedPlaneNode!, imageName: selectedImageName)
            
            // MARK: Close the modal
            dismiss(animated: true)
        } else {
            // MARK: Handle icon selection
            
            let selectedIconName = iconNames[indexPath.item]
            
            // MARK: Create new icon at random position
            // Generate a random position within the safe area of the wall
            delegate?.iconPosition = (x: Float.random(in: 0.2..<0.8), y: Float.random(in: 0.2..<0.8))
            
            // MARK: Update icon and render
            delegate?.currentIconName = selectedIconName
            delegate?.addIconToWall()
            
            // MARK: Close the modal
            dismiss(animated: true)
        }
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

/// Custom collection view cell for displaying selectable system icons
///
/// Visual features:
/// - Displays a system icon (SF Symbols)
/// - Shows a blue border selection indicator when selected
/// - Uses tint color to colorize the icon
/// - Matches the visual style of ImagePickerCell
///
class IconSelectorCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    /// Image view for displaying the system icon
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
        iconView.contentMode = .scaleAspectFit // Center and scale icon
        iconView.tintColor = .systemBlue // Color the system icon blue
        iconView.backgroundColor = .systemGray6 // Background color
        iconView.layer.cornerRadius = 8
        iconView.clipsToBounds = true
        
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
    
    /// Configures the cell with a system icon and selection state
    /// - Parameters:
    ///   - iconName: Name of the SF Symbol to display
    ///   - isSelected: Whether the cell is currently selected
    func configure(with iconName: String, isSelected: Bool) {
        iconView.image = UIImage(systemName: iconName)
        selectionIndicator.isHidden = !isSelected
    }
}
