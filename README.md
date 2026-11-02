# PowerShell File Integrity Monitoring (FIM) 🔐

<h2>Project Description</h2>

<p>This project implements a PowerShell-based File Integrity Monitoring (FIM) tool designed to detect unauthorized or unexpected changes within a monitored directory.</p>

<p>Using the SHA-512 hashing algorithm, the application establishes a baseline of monitored files and periodically compares their current hashes against the original reference values. When a discrepancy is detected, the script identifies the event and records it for review.</p>

<p>The project began as a basic file integrity monitoring implementation and was subsequently expanded with modular functions, recursive directory scanning, input validation, error handling, alert deduplication, and structured event logging.</p>

<hr>

<h2>Project Objectives</h2>

<ul>
<li>Calculate SHA-512 hashes to establish file integrity baselines.</li>
<li>Detect newly created, modified, deleted, and restored files.</li>
<li>Implement continuous monitoring through periodic directory scans.</li>
<li>Extend monitoring to include nested directories.</li>
<li>Reduce repetitive alerts through state comparison and alert deduplication.</li>
<li>Implement input validation and error handling.</li>
<li>Maintain timestamped security event records in CSV format.</li>
<li>Develop a modular PowerShell application using reusable functions.</li>
</ul>

<h2>Tools and Technologies Used 🧪</h2>

<table>
<tr>
<th>Category</th>
<th>Technology</th>
</tr>
<tr>
<td>Scripting Language</td>
<td>PowerShell</td>
</tr>
<tr>
<td>Hashing Algorithm</td>
<td>SHA-512</td>
</tr>
<tr>
<td>File Enumeration</td>
<td><code>Get-ChildItem</code></td>
</tr>
<tr>
<td>Hash Calculation</td>
<td><code>Get-FileHash</code></td>
</tr>
<tr>
<td>Data Storage</td>
<td>CSV</td>
</tr>
<tr>
<td>Data Structures</td>
<td>PowerShell Hashtables and Custom Objects</td>
</tr>
<tr>
<td>Development Environment</td>
<td>Visual Studio Code / PowerShell</td>
</tr>
</table>

<hr>

<h2>1. Project Architecture and Directory Structure</h2>

<p>The project uses a modular structure that separates the PowerShell implementation, monitored test files, generated data, and documentation evidence.</p>

<pre>
PowerShell-File-Integrity-Monitor/
│
├── README.md
├── Fim2.ps1
├── Original/
│   ├── Initial-Implementation.ps1
│   └── Josh-Madakor-Tutorial.ps1
│
├── Files/
│   ├── testfile1.txt
│   ├── testfile2.txt
│   └── Subfolder/
│       └── nestedfile.txt
│
├── Screenshots/
│   ├── 01-project-structure.png
│   ├── 02-baseline-generation.png
│   ├── 03-file-modification.png
│   ├── 04-alert-deduplication.png
│   ├── 05-recursive-monitoring.png
│   └── 06-event-logging.png
│
└── .gitignore
</pre>

<p><strong>Generated files:</strong></p>

<ul>
<li><code>baseline.csv</code> stores the reference file paths and SHA-512 hashes.</li>
<li><code>fim_events.csv</code> stores detected file integrity events.</li>
</ul>

<p>These files are generated during execution and are excluded from version control through <code>.gitignore</code>.</p>

<h2>2. Baseline Generation and Hash Collection</h2>

<p>The first stage establishes a trusted reference state for the monitored directory. When the user selects the baseline creation option, the script enumerates the monitored files and calculates an individual SHA-512 hash for each file.</p>

<p>The resulting records contain two primary values:</p>

<ul>
<li><strong>FilePath:</strong> The full path identifying the monitored file.</li>
<li><strong>Hash:</strong> The SHA-512 digest representing the file's current contents.</li>
</ul>

<p>The collected records are stored in <code>baseline.csv</code>. This file becomes the reference point against which subsequent monitoring scans are evaluated.</p>

<p>The implementation uses <code>Get-FileHash</code> with the SHA-512 algorithm to generate file fingerprints.</p>

```powershell
Get-FileHash -LiteralPath $FilePath -Algorithm SHA512
```

<p>Before replacing an existing baseline, the script writes the new records to a temporary file. The completed temporary file is then moved into place, reducing the likelihood of leaving behind an incomplete baseline if an export operation fails.</p>

<!-- SCREENSHOT 2: BASELINE GENERATION
Capture: PowerShell output showing successful baseline creation, number of files recorded, and sample baseline entries.
Image: Screenshots/02-baseline-generation.png
-->

<h2>3. Baseline Import and Validation</h2>

<p>When continuous monitoring begins, the application imports the previously generated CSV baseline.</p>

<p>The imported records are validated before monitoring proceeds. The script checks that the baseline exists, that the expected fields are present, and that the stored file paths and SHA-512 hashes contain valid data.</p>

<p>The baseline is then loaded into a PowerShell hashtable, using file paths as keys and their corresponding expected hashes as values.</p>

<p>This structure allows the application to retrieve the expected hash associated with a file path efficiently during subsequent comparisons.</p>

```powershell
$baseline = @{}

$baseline[$filePath] = $hash
```

<p>The original baseline remains the trusted reference during monitoring. It is not automatically overwritten when a file changes.</p>

<h2>4. Continuous File Integrity Monitoring</h2>

<p>After the baseline is imported, the script enters a continuous monitoring loop. During each iteration, the application scans the monitored directory, calculates the current SHA-512 hashes, and compares the resulting file state against the baseline and previously observed state.</p>

<p>The monitoring interval is configurable through the <code>$pollingInterval</code> variable. The current implementation uses a one-second interval between scans.</p>

```powershell
$pollingInterval = 1

Start-Sleep -Seconds $pollingInterval
```

<p>Comparing both the original baseline and the previously observed state allows the application to distinguish between different file events and avoid repeatedly reporting an unchanged condition.</p>

<h3>4.1 File Creation Detection</h3>

<p>When a file appears in the monitored directory but does not exist in the original baseline, the application identifies it as a newly created file.</p>

<p>The event is reported as <code>CREATED</code> and recorded with the file path and current hash.</p>

<!-- SCREENSHOT 3: FILE CREATION
Capture: PowerShell output displaying a CREATED event after adding a new file.
-->

<h3>4.2 File Modification Detection</h3>

<p>For files already present in the baseline, the current SHA-512 hash is compared against the expected hash.</p>

<p>If the hashes differ, the file contents have changed. The application generates a <code>MODIFIED</code> event containing the expected and current hash values.</p>

<p>The previous observed state is also evaluated to determine whether the modification represents a new event or an already reported condition.</p>

<!-- SCREENSHOT 4: FILE MODIFICATION
Capture: PowerShell output displaying a MODIFIED event after changing an existing file.
Image: Screenshots/03-file-modification.png
-->

<h3>4.3 File Deletion Detection</h3>

<p>The application also checks whether files previously observed during monitoring are still present in the current scan.</p>

<p>If a previously observed file is no longer found, the application generates a <code>DELETED</code> event.</p>

<p>This allows the monitor to identify missing files in addition to changes in file contents.</p>

<h3>4.4 File Restoration Detection</h3>

<p>If a previously modified file returns to its original baseline hash, the application identifies the change as a restoration event.</p>

<p>The event is recorded as <code>RESTORED</code>, distinguishing a return to the trusted reference state from an ordinary modification.</p>

<h2>5. Recursive Directory Monitoring</h2>

<p>The monitoring implementation supports recursive file enumeration. Rather than examining only the top-level directory, the application searches through nested folders and includes their files in the monitoring process.</p>

<p>This is implemented through <code>Get-ChildItem</code> with the <code>-Recurse</code> parameter.</p>

```powershell
Get-ChildItem -LiteralPath $Path -File -Recurse -Force
```

<p>Recursive enumeration allows the monitor to detect file activity throughout the monitored directory structure, including files located several levels below the root folder.</p>

<p>For testing, a nested subfolder and sample file were created to verify that the application could identify changes outside the top-level directory.</p>

<!-- SCREENSHOT 5: RECURSIVE MONITORING
Capture: A CREATED or MODIFIED event involving a file inside Files/Subfolder.
Image: Screenshots/05-recursive-monitoring.png
-->

<h2>6. Alert Deduplication and Event Reporting</h2>

<p>One of the improvements made to the monitoring logic was the introduction of alert deduplication.</p>

<p>Without state tracking, a continuous monitoring application can repeatedly report the same file modification or deletion during every scan. This can produce unnecessary console output and make meaningful events harder to identify.</p>

<p>To address this, the application maintains separate representations of:</p>

<ul>
<li><strong>Baseline:</strong> The original trusted file state.</li>
<li><strong>PreviousState:</strong> The most recently observed file state.</li>
<li><strong>CurrentState:</strong> The file state collected during the latest scan.</li>
</ul>

<p>By comparing these states, the application can determine whether a file event is new, whether a previously observed condition has changed, or whether a file has returned to its original state.</p>

<h3>6.1 Structured Event Logging</h3>

<p>Detected events are displayed in the PowerShell console and written to <code>fim_events.csv</code>.</p>

<p>Each event record contains the following fields:</p>

<table>
<tr>
<th>Field</th>
<th>Description</th>
</tr>
<tr>
<td><code>Timestamp</code></td>
<td>Date and time the event was detected.</td>
</tr>
<tr>
<td><code>Event</code></td>
<td>Event classification: CREATED, MODIFIED, DELETED, or RESTORED.</td>
</tr>
<tr>
<td><code>FilePath</code></td>
<td>Full path of the affected file.</td>
</tr>
<tr>
<td><code>ExpectedHash</code></td>
<td>Original baseline hash, when applicable.</td>
</tr>
<tr>
<td><code>CurrentHash</code></td>
<td>Hash observed during the current scan.</td>
</tr>
</table>

<p>The event log provides a structured record of detected activity that can be reviewed independently of the live monitoring console.</p>

<!-- SCREENSHOT 6: EVENT LOGGING
Capture: fim_events.csv opened in a spreadsheet or text editor, showing timestamps, event types, file paths, and hash values.
Image: Screenshots/06-event-logging.png
-->

<h2>7. Input Validation and Error Handling</h2>

<p>The implementation includes validation and error-handling measures to make execution more predictable and to provide useful feedback when an operation cannot be completed.</p>

<ul>
<li>Checks that the monitored directory exists before scanning.</li>
<li>Validates the imported baseline before using it.</li>
<li>Uses terminating errors where appropriate so failures can be handled through <code>try</code> and <code>catch</code> blocks.</li>
<li>Handles file hashing and CSV logging failures with error messages.</li>
<li>Normalizes menu input to make option selection more consistent.</li>
</ul>

<p>These measures help prevent invalid input or unexpected file operations from silently producing unreliable monitoring results.</p>

<h2>8. Testing and Validation</h2>

<p>The application was tested in a controlled environment using sample files within the monitored directory. Each test was designed to verify a specific detection or monitoring behavior.</p>

<table>
<tr>
<th>Test</th>
<th>Expected Result</th>
<th>Result</th>
</tr>
<tr>
<td>Baseline generation</td>
<td>Create a CSV baseline containing file paths and SHA-512 hashes.</td>
<td>Passed</td>
</tr>
<tr>
<td>Baseline import</td>
<td>Load and validate an existing baseline.</td>
<td>Passed</td>
</tr>
<tr>
<td>File creation</td>
<td>Detect a file absent from the original baseline.</td>
<td>Passed</td>
</tr>
<tr>
<td>File modification</td>
<td>Detect a mismatch between the current and expected hash.</td>
<td>Passed</td>
</tr>
<tr>
<td>File deletion</td>
<td>Detect a previously observed file that is now missing.</td>
<td>Passed</td>
</tr>
<tr>
<td>File restoration</td>
<td>Detect a file returning to its original baseline hash.</td>
<td>Passed</td>
</tr>
<tr>
<td>Alert deduplication</td>
<td>Avoid repeatedly reporting an unchanged event condition.</td>
<td>Passed</td>
</tr>
<tr>
<td>Recursive monitoring</td>
<td>Detect activity in nested directories.</td>
<td>Passed</td>
</tr>
<tr>
<td>CSV event logging</td>
<td>Record detected events with timestamps and relevant file information.</td>
<td>Passed</td>
</tr>
</table>

<p>Testing was performed using controlled file creation, modification, deletion, and restoration operations. Results were verified through console output and the generated event log.</p>

<h2>9. Security Considerations and Limitations</h2>

<p>Although the project demonstrates several core file integrity monitoring concepts, it is a learning implementation rather than a production-grade security monitoring solution.</p>

<h3>Baseline Protection</h3>

<p>The baseline serves as the trusted reference for file comparisons. However, the current implementation does not cryptographically authenticate or independently protect the baseline file. An attacker with sufficient access could potentially modify both a monitored file and its baseline record.</p>

<h3>Polling-Based Monitoring</h3>

<p>The application relies on periodic directory scans rather than real-time filesystem event notifications. Changes that occur and reverse between scans may not be detected.</p>

<h3>Event Log Protection</h3>

<p>The event log is stored locally in CSV format. It is not independently protected against deletion or modification by a user with sufficient filesystem permissions.</p>

<h3>Limited Attribution</h3>

<p>The application identifies file integrity events but does not determine which user or process performed the operation.</p>

<h3>Potential Future Improvements</h3>

<ul>
<li>Protect baseline files through digital signatures or secure storage.</li>
<li>Implement centralized event logging and monitoring.</li>
<li>Explore real-time filesystem monitoring mechanisms.</li>
<li>Capture additional context, including user and process attribution.</li>
<li>Improve monitoring performance for larger directory structures.</li>
<li>Introduce configurable monitoring intervals and exclusions.</li>
<li>Expand alerting through email, SIEM, or other notification integrations.</li>
</ul>

<h2>10. Key Takeaways</h2>

<ul>
<li><strong>File Integrity:</strong> SHA-512 hashing provides a way to identify changes in file contents by comparing calculated hashes against trusted reference values.</li>
<li><strong>PowerShell Automation:</strong> Modular functions and reusable logic make it easier to organize and maintain monitoring operations.</li>
<li><strong>State Management:</strong> Comparing baseline, previous, and current states makes it possible to distinguish file events and reduce repetitive alerts.</li>
<li><strong>Recursive Monitoring:</strong> Directory traversal allows monitoring to extend beyond a single folder level.</li>
<li><strong>Event Reporting:</strong> Structured CSV logging creates a record of detected activity for later review.</li>
<li><strong>Security Limitations:</strong> A monitoring tool must also protect its baseline and logs, account for monitoring gaps, and consider event attribution.</li>
</ul>

<h2>Conclusion</h2>

<p>This project provided practical experience with PowerShell scripting, cryptographic hashing, file system enumeration, state comparison, error handling, and structured event logging.</p>

<p>Starting with a basic file integrity monitoring implementation, the project evolved into a more modular application capable of detecting multiple file events across nested directories while maintaining a structured event history.</p>

<p>The project also highlighted important considerations when designing security monitoring tools, particularly the need to protect trusted reference data, maintain reliable event records, and understand the limitations of polling-based detection.</p>

<hr>

<p><em>Project developed as a hands-on cybersecurity and PowerShell automation lab.</em></p>
