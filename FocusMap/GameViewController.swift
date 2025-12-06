//
//  GameViewController.swift
//  FocusMap
//
//  Created by Hieu on 5/12/25.
//

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
    /// - Returns: A new SCNVector3 with magnitude 1 in the same direction
    func normalized() -> SCNVector3 {
        let length = sqrt(x*x + y*y + z*z)
        guard length > 0 else { return SCNVector3(0, 0, 0) }
        return SCNVector3(x/length, y/length, z/length)
    }
}

// MARK: - GameViewController

/// Main view controller managing the 3D SceneKit view and user interactions
/// Handles plane creation, selection, image mapping, and camera controls
class GameViewController: UIViewController {
    
    // MARK: - Properties
    
    /// Reference to the SceneKit view displaying the 3D scene
    var sceneView: SCNView?
    
    /// Reference to the camera node for zoom and navigation
    var cameraNode: SCNNode?
    
    /// Minimum zoom distance constraint (closest camera can get)
    let minZoomDistance: Float = 2.0
    
    /// Maximum zoom distance constraint (farthest camera can be)
    let maxZoomDistance: Float = 20.0
    
    /// Currently selected plane node from user interaction
    var selectedPlaneNode: SCNNode?
    
    /// Dictionary mapping plane names to their assigned image names
    /// Format: ["bottomPlane": "vector1", "backPlane": "vector2", ...]
    var planeMappings: [String: String] = [:]
    
    /// UserDefaults key for persisting plane-to-image mappings
    let planeMappingsKey = "planeMappings"
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Restore previously saved plane-to-image mappings from persistent storage
        if let saved = UserDefaults.standard.dictionary(forKey: planeMappingsKey) as? [String: String] {
            planeMappings = saved
        }
        
        // Initialize and configure the SceneKit view with full screen coverage
        let sceneView = SCNView(frame: self.view.bounds)
        sceneView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sceneView.scene = createScene()
        sceneView.backgroundColor = UIColor.black
        sceneView.allowsCameraControl = false // Manual camera control via gestures
        
        // Add tap gesture recognizer for selecting planes
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        sceneView.addGestureRecognizer(tapGesture)
        
        // Add pinch gesture recognizer for zoom in/out functionality
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        sceneView.addGestureRecognizer(pinchGesture)
        
        // Store references and add view to hierarchy
        self.sceneView = sceneView
        self.cameraNode = sceneView.scene?.rootNode.childNodes.first { $0.camera != nil }
        self.view.addSubview(sceneView)
        
        // Apply any previously saved images to the planes
        applyMappedImages()
    }
    
    // MARK: - Gesture Handlers
    
    /// Handles tap gestures on the scene view to select planes and open image picker
    /// - Parameter gesture: The tap gesture recognizer
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let sceneView = gesture.view as? SCNView else { return }
        let location = gesture.location(in: sceneView)
        
        // Perform hit test to find all nodes at tap location
        let hitResults = sceneView.hitTest(location, options: [:])
        
        for result in hitResults {
            let tappedNode = result.node
            
            // Verify the tapped node has valid geometry with materials
            guard let geometry = tappedNode.geometry else { continue }
            let materials = geometry.materials
            guard !materials.isEmpty else { continue }
            
            // Check visibility using both node opacity and material transparency
            let nodeVisible = tappedNode.presentation.opacity > 0.0
            let hasVisibleMaterial = materials.contains { material in
                // Transparency range: 1.0 (opaque) to 0.0 (transparent)
                // Consider visible if transparency > 0 (not fully transparent)
                material.transparency > 0.0
            }
            guard nodeVisible && hasVisibleMaterial else { continue }
            
            // Found a clickable, visible plane
            print("Tapped plane: \(tappedNode.name ?? "Unknown")")
            
            // Provide visual feedback with highlight animation
            highlightPlane(tappedNode)
            
            // Select the plane and show image picker modal
            selectedPlaneNode = tappedNode
            showImagePickerModal()
            break
        }
    }
    
    /// Plays a highlight animation on the specified plane node
    /// Animation dims the plane opacity briefly, then restores it
    /// - Parameter node: The plane node to highlight
    func highlightPlane(_ node: SCNNode) {
        let action = SCNAction.sequence([
            SCNAction.run { _ in
                node.opacity = 0.7 // Dim the plane
            },
            SCNAction.wait(duration: 0.1),
            SCNAction.run { _ in
                node.opacity = 1.0 // Restore original opacity
            }
        ])
        node.runAction(action)
    }
    
    /// Handles pinch gestures for camera zoom in/out functionality
    /// Maintains camera direction while adjusting distance to origin
    /// - Parameter gesture: The pinch gesture recognizer
    @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let cameraNode = cameraNode else { return }
        
        // Calculate new distance based on pinch scale factor
        let scale = Float(gesture.scale)
        let currentDistance = cameraNode.position.distance(to: SCNVector3(0, -0.5, 0))
        let newDistance = currentDistance / scale
        
        // Constrain zoom distance to defined min/max bounds
        let clampedDistance = max(minZoomDistance, min(maxZoomDistance, newDistance))
        
        // Recalculate camera position maintaining its direction vector
        let direction = cameraNode.position.normalized()
        cameraNode.position = SCNVector3(
            direction.x * clampedDistance,
            direction.y * clampedDistance,
            direction.z * clampedDistance
        )
        
        // Reset gesture scale for next pinch calculation
        gesture.scale = 1.0
    }
    
    // MARK: - Scene Setup
    
    /// Creates and configures the 3D SceneKit scene with planes, camera, and lighting
    /// - Returns: Configured SCNScene with all scene elements
    func createScene() -> SCNScene {
        let scene = SCNScene()
        
        // Scene parameters
        let size: CGFloat = 4.0
        let half = size / 2.0
        
        // Helper function to create materials with front and back colors
        // Allows different colors when viewed from different sides
        /// Creates two-sided materials for a plane with distinct front and back colors
        /// - Parameters:
        ///   - front: Color for the front face (along plane normal direction)
        ///   - back: Color for the back face (opposite to normal direction)
        ///   - doubleSided: Whether materials should be double-sided
        /// - Returns: Array of SCNMaterial objects [frontMaterial, backMaterial]
        func twoSidedMaterials(front: UIColor, back: UIColor, doubleSided: Bool = true) -> [SCNMaterial] {
            let frontMat = SCNMaterial()
            frontMat.diffuse.contents = front
            frontMat.isDoubleSided = doubleSided
            
            let backMat = SCNMaterial()
            backMat.diffuse.contents = back
            backMat.isDoubleSided = doubleSided
            
            // For SCNPlane: first material = front faces, second material = back faces
            return [frontMat, backMat]
        }
        
        // MARK: Bottom Plane (Y = -half, normal pointing up)
        let bottomPlane = SCNPlane(width: size, height: size)
        bottomPlane.materials = twoSidedMaterials(
            front: UIColor.systemGreen.withAlphaComponent(0.6),   // Visible from above
            back: UIColor.systemRed.withAlphaComponent(0.3)       // Visible from below
        )
        let bottomNode = SCNNode(geometry: bottomPlane)
        bottomNode.name = "bottomPlane"
        bottomNode.position = SCNVector3(0, Float(-half), 0)
        // Rotate plane from default +Z facing to +Y facing
        bottomNode.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        scene.rootNode.addChildNode(bottomNode)
        
        // MARK: Back Plane (Z = -half, normal pointing forward)
        let backPlane = SCNPlane(width: size, height: size)
        backPlane.materials = twoSidedMaterials(
            front: UIColor.systemBlue.withAlphaComponent(0.6),    // Visible from front
            back: UIColor.systemOrange.withAlphaComponent(0.3)    // Visible from behind
        )
        let backNode = SCNNode(geometry: backPlane)
        backNode.name = "backPlane"
        backNode.position = SCNVector3(0, 0, Float(-half))
        // Default plane already faces +Z direction, Y-up orientation
        backNode.eulerAngles = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(backNode)
        
        // MARK: Left Plane (X = -half, normal pointing left)
        let leftPlane = SCNPlane(width: size, height: size)
        leftPlane.materials = twoSidedMaterials(
            front: UIColor.systemYellow.withAlphaComponent(0.6),  // Visible from +X side
            back: UIColor.systemPurple.withAlphaComponent(0.3)    // Visible from -X side
        )
        let leftNode = SCNNode(geometry: leftPlane)
        leftNode.name = "leftPlane"
        leftNode.position = SCNVector3(Float(-half), 0, 0)
        // Rotate -90° around Y axis to face -X direction
        leftNode.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        scene.rootNode.addChildNode(leftNode)
        
        // MARK: Right Plane (Optional)
        // Uncomment to add the right face (X = +half, normal pointing right)
        /*
        let rightPlane = SCNPlane(width: size, height: size)
        rightPlane.materials = twoSidedMaterials(
            front: UIColor.systemTeal.withAlphaComponent(0.6),
            back: UIColor.systemPink.withAlphaComponent(0.3)
        )
        let rightNode = SCNNode(geometry: rightPlane)
        rightNode.position = SCNVector3(Float(half), 0, 0)
        // Rotate +90° around Y axis to face +X direction
        rightNode.eulerAngles = SCNVector3(0, Float.pi / 2, 0)
        scene.rootNode.addChildNode(rightNode)
        */
        
        // MARK: Camera Setup
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(5, 2, 5) // Positioned for isometric-like view
        cameraNode.look(at: SCNVector3(0, -0.5, 0)) // Focus on center slightly below origin
        scene.rootNode.addChildNode(cameraNode)
        
        // MARK: Lighting Setup
        
        // Main omnidirectional light for bright illumination
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(5, 5, 5) // Position above and to the side
        scene.rootNode.addChildNode(lightNode)
        
        // Ambient light for fill illumination on shadowed areas
        let ambientLight = SCNNode()
        ambientLight.light = SCNLight()
        ambientLight.light!.type = .ambient
        ambientLight.light!.color = UIColor(white: 0.4, alpha: 1.0)
        scene.rootNode.addChildNode(ambientLight)
        
        return scene
    }
    
    // MARK: - Interface Orientation
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        // Support all orientations on iPad, all but upside-down on iPhone
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true // Hide status bar for immersive 3D view
    }
    
    // MARK: - Image Picker Modal
    
    /// Presents the image picker modal as a bottom sheet for plane texture selection
    func showImagePickerModal() {
        let imagePickerVC = ImagePickerModalViewController()
        imagePickerVC.delegate = self
        
        // Pass the currently selected image for visual indication
        if let planeName = selectedPlaneNode?.name {
            imagePickerVC.selectedImageName = planeMappings[planeName]
        }
        
        // Configure as bottom sheet presentation (iOS 15+)
        if #available(iOS 15.0, *) {
            if let sheet = imagePickerVC.sheetPresentationController {
                sheet.detents = [.custom(resolver: { _ in 160 })] // Fixed height of 160pt
                sheet.prefersGrabberVisible = true // Show drag handle
            }
        }
        
        present(imagePickerVC, animated: true)
    }
    
    /// Applies all saved image mappings to their corresponding plane nodes
    /// Called during initialization and when restoring from persistent storage
    func applyMappedImages() {
        guard let scene = sceneView?.scene else { return }
        
        // Iterate through all plane nodes and apply their mapped images
        for node in scene.rootNode.childNodes {
            if let planeName = node.name, let imageName = planeMappings[planeName] {
                applyImageToNode(node, imageName: imageName)
            }
        }
    }
    
    /// Applies a vector image to a plane node's material
    /// - Parameters:
    ///   - node: The plane node to texture
    ///   - imageName: The name of the image asset (PDF/SVG supported)
    func applyImageToNode(_ node: SCNNode, imageName: String) {
        // Load the vector image from Assets
        guard let image = UIImage(named: imageName) else { return }
        
        // Update the plane's material with the new image
        if let geometry = node.geometry {
            let material = SCNMaterial()
            material.diffuse.contents = image
            material.isDoubleSided = true // Visible from both sides
            geometry.materials = [material]
        }
    }
}

// MARK: - Image Picker Modal Controller

/// Modal view controller for selecting and assigning images to plane textures
/// Displays a horizontal collection view of available vector images
class ImagePickerModalViewController: UIViewController, UICollectionViewDelegate, UICollectionViewDataSource {
    
    // MARK: - Properties
    
    /// Weak reference to parent GameViewController for delegating image selection
    weak var delegate: GameViewController?
    
    /// Currently selected image name (for visual highlighting)
    var selectedImageName: String?
    
    /// List of available vector image asset names
    let imageNames = ["vector1", "vector2", "vector3", "vector4", "vector5", "vector6"]
    
    /// Collection view for displaying selectable image thumbnails
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    
    // MARK: - Lifecycle Methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        setupCollectionView()
    }
    
    // MARK: - Setup Methods
    
    /// Configures the collection view layout and constraints
    private func setupCollectionView() {
        // Configure horizontal scrolling grid layout
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 120, height: 120)
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        
        collectionView.setCollectionViewLayout(layout, animated: false)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.showsVerticalScrollIndicator = false
        collectionView.backgroundColor = .systemBackground
        collectionView.isScrollEnabled = true
        
        // Register custom cell class
        collectionView.register(ImagePickerCell.self, forCellWithReuseIdentifier: "cell")
        
        // Add to view hierarchy and apply constraints
        view.addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - UICollectionViewDataSource
    
    /// Returns the number of images available for selection
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return imageNames.count
    }
    
    /// Configures and returns a cell for the collection view
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ImagePickerCell
        
        let imageName = imageNames[indexPath.item]
        let isSelected = imageName == selectedImageName
        cell.configure(with: imageName, isSelected: isSelected)
        
        return cell
    }
    
    // MARK: - UICollectionViewDelegate
    
    /// Handles image selection from the collection view
    /// Updates the plane texture and saves the mapping
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let selectedImageName = imageNames[indexPath.item]
        
        // Ensure a plane is selected in the parent view controller
        guard let planeName = delegate?.selectedPlaneNode?.name else {
            dismiss(animated: true)
            return
        }
        
        // Update the plane-to-image mapping in memory
        delegate?.planeMappings[planeName] = selectedImageName
        
        // Persist the updated mapping to UserDefaults
        UserDefaults.standard.set(
            delegate?.planeMappings,
            forKey: delegate?.planeMappingsKey ?? "planeMappings"
        )
        
        // Apply the selected image to the plane node
        delegate?.applyImageToNode(delegate!.selectedPlaneNode!, imageName: selectedImageName)
        
        // Close the modal
        dismiss(animated: true)
    }
}

// MARK: - Image Picker Cell

/// Custom collection view cell for displaying selectable images with selection indicator
class ImagePickerCell: UICollectionViewCell {
    
    // MARK: - Properties
    
    /// Image view for displaying the thumbnail
    private let imageView = UIImageView()
    
    /// Visual indicator shown when the cell is selected
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
    
    /// Configures the cell's UI elements and constraints
    private func setupUI() {
        // Add subviews
        contentView.addSubview(imageView)
        contentView.addSubview(selectionIndicator)
        
        // Configure image view
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.backgroundColor = .systemGray6 // Placeholder background
        
        // Configure selection indicator (blue border)
        selectionIndicator.layer.borderColor = UIColor.systemBlue.cgColor
        selectionIndicator.layer.borderWidth = 3
        selectionIndicator.layer.cornerRadius = 8
        selectionIndicator.isHidden = true // Hidden until selected
        
        // Enable Auto Layout
        imageView.translatesAutoresizingMaskIntoConstraints = false
        selectionIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        // Apply constraints
        NSLayoutConstraint.activate([
            // Image view with padding
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
