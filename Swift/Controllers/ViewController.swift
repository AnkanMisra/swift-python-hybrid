import UIKit
import Combine

class ViewController: UIViewController {
    
    private let stackView = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let tableView = UITableView()
    
    private var dataSource: [String] = []
    private var cancellables = Set<AnyCancellable>()
    private var isLoading = false {
        didSet {
            updateLoadingState()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupBindings()
        loadInitialData()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        setupNavigationBar()
        setupStackView()
        setupLabels()
        setupButton()
        setupProgressView()
        setupTableView()
    }
    
    private func setupNavigationBar() {
        title = "Main Dashboard"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        let refreshButton = UIBarButtonItem(
            barButtonSystemItem: .refresh,
            target: self,
            action: #selector(refreshData)
        )
        navigationItem.rightBarButtonItem = refreshButton
    }
    
    private func setupStackView() {
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
    }
    
    private func setupLabels() {
        titleLabel.text = "Welcome to the App"
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        
        subtitleLabel.text = "Manage your data efficiently"
        subtitleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
    }
    
    private func setupButton() {
        actionButton.setTitle("Load Data", for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        actionButton.backgroundColor = .systemBlue
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 8
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        
        actionButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        stackView.addArrangedSubview(actionButton)
    }
    
    private func setupProgressView() {
        progressView.isHidden = true
        progressView.progressTintColor = .systemBlue
        stackView.addArrangedSubview(progressView)
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.backgroundColor = .systemBackground
        tableView.layer.cornerRadius = 8
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            tableView.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 20),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }
    
    private func setupBindings() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshData()
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        dataSource = [
            "Dashboard Overview",
            "Recent Activity",
            "User Statistics",
            "System Status",
            "Settings"
        ]
        tableView.reloadData()
    }
    
    @objc private func actionButtonTapped() {
        simulateDataLoading()
    }
    
    @objc private func refreshData() {
        loadInitialData()
        showSuccessMessage("Data refreshed successfully")
    }
    
    private func simulateDataLoading() {
        isLoading = true
        
        let loadingPublisher = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .scan(0.0) { progress, _ in
                return min(progress + 0.1, 1.0)
            }
            .handleEvents(receiveOutput: { [weak self] progress in
                self?.progressView.progress = Float(progress)
            })
            .filter { $0 >= 1.0 }
            .first()
        
        loadingPublisher
            .delay(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.completeDataLoading()
            }
            .store(in: &cancellables)
    }
    
    private func completeDataLoading() {
        isLoading = false
        
        let newData = [
            "New Item \(Int.random(in: 1...100))",
            "Updated Entry \(Int.random(in: 1...100))",
            "Fresh Content \(Int.random(in: 1...100))"
        ]
        
        dataSource.append(contentsOf: newData)
        
        UIView.animate(withDuration: 0.3) {
            self.tableView.reloadData()
        }
        
        showSuccessMessage("Data loaded successfully!")
    }
    
    private func updateLoadingState() {
        UIView.animate(withDuration: 0.3) {
            self.actionButton.isEnabled = !self.isLoading
            self.progressView.isHidden = !self.isLoading
            
            if self.isLoading {
                self.actionButton.setTitle("Loading...", for: .normal)
                self.actionButton.backgroundColor = .systemGray
            } else {
                self.actionButton.setTitle("Load Data", for: .normal)
                self.actionButton.backgroundColor = .systemBlue
                self.progressView.progress = 0.0
            }
        }
    }
    
    private func showSuccessMessage(_ message: String) {
        let alert = UIAlertController(title: "Success", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let selectedIndexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectedIndexPath, animated: animated)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        UIView.animate(withDuration: 0.5, delay: 0.2, options: .curveEaseInOut) {
            self.stackView.alpha = 1.0
            self.tableView.alpha = 1.0
        }
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = dataSource[indexPath.row]
        cell.accessoryType = .disclosureIndicator
        return cell
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let selectedItem = dataSource[indexPath.row]
        let alert = UIAlertController(
            title: "Selected Item",
            message: "You selected: \(selectedItem)",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 50
    }
}
