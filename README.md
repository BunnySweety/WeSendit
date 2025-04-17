# WeSendit Node Docker Setup

This repository provides a Docker Compose setup to easily run and manage a WeSendit storage node. This guide assumes node configuration and identity are primarily handled via a web-based onboarding process after the initial container start.

## Prerequisites

Before you begin, ensure you have the following installed/ready:

1.  **Docker:** [Install Docker](https://docs.docker.com/engine/install/)
2.  **Docker Compose:** [Install Docker Compose](https://docs.docker.com/compose/install/) (Often included with Docker Desktop).
3.  **Web3 Wallet:** A compatible Web3 wallet (e.g., MetaMask) ready for the node onboarding process. This process may require WSI tokens or specific network configurations in your wallet. Please refer to official WeSendit onboarding guides.
4.  **Basic Terminal/Command Line Knowledge:** You will need to run commands in a terminal.
5.  **Git (Optional):** To clone this repository. Otherwise, download the files manually.

## Included Files

* **`docker-compose.yml`:** Defines the WeSendit node service, volumes (for persistent storage), and ports for Docker Compose.
* **`.env`:** Environment file used by `docker-compose.yml` to configure host paths (for persistence) and ports. **You will need to edit this.**
* **`node_check.sh`:** A utility script (requires execution permissions) to check system requirements, port accessibility, and Docker container status for your node.

## Setup Instructions

1.  **Get the Files:**
    * Clone this repository: `git clone <repository_url>`
    * OR download the `docker-compose.yml`, `.env`, and `node_check.sh` files into a dedicated directory.

2.  **Navigate to Directory:**
    Open your terminal and change into the directory containing the downloaded files:
    ```bash
    cd /path/to/your/wesendit-setup-directory
    ```

3.  **Configure Environment (`.env`):**
    * Open the `.env` file in a text editor.
    * **Set `TARGET_PATH`:** This is critical for persistence. Replace the placeholder `/path/to/your/wesendit/node/files` with the **absolute path** on your host machine where you want the node's persistent data (`data` subdirectory) and configuration (`config` subdirectory, *populated during onboarding*) to be stored.
        * *Example Linux/macOS:* `TARGET_PATH=/srv/wesendit_node`
        * *Example Windows:* `TARGET_PATH=C:/wesendit_node`
        * **Important:** Ensure that Docker has permission to read and write to this location. Docker might create the subdirectories if they don't exist. The configuration generated during onboarding will be saved here.
    * **(Optional) Adjust Ports:** Modify `OUTWARD_PORT` (default: 41631) and `FRONTEND_PORT` (default: 41630) if you need the node to be accessible via different ports on your host machine. Ensure these ports are not already in use.

4.  **Configure Firewall:**
    * Ensure that the ports specified by `OUTWARD_PORT` (default 41631) and `FRONTEND_PORT` (default 41630) in your `.env` file are **open** on your host machine's firewall and any network firewalls/routers.
    * The `OUTWARD_PORT` (41631) typically needs to be accessible from the internet for P2P connections.
    * The `FRONTEND_PORT` (41630) needs to be accessible from your browser for the onboarding process and potentially later for a dashboard.
    * You can use the `node_check.sh` script later to help verify port accessibility.

## Running the Node & Onboarding

1.  **Start the container in detached mode:**
    ```bash
    docker-compose up -d
    ```
    Docker Compose will pull the `wesendit/node:latest` image (if not already present) and start the container. Allow a minute for the container to initialize.

2.  **Complete Onboarding via Web Interface:**
    * Open a web browser and navigate to the node's frontend interface. This is typically `http://<your_server_ip_or_hostname>:${FRONTEND_PORT}`.
    * If running on the same machine, use `http://localhost:41630` (replace `41630` if you changed `FRONTEND_PORT` in `.env`).
    * Follow the on-screen instructions provided by WeSendit. This will likely involve:
        * Connecting your Web3 wallet (e.g., MetaMask).
        * Authorizing transactions or signing messages.
        * Completing registration steps.
    * This onboarding process should configure your node's identity and save the necessary configuration files persistently within the volume mapped to `${TARGET_PATH}/config`.

## Checking Node Status

After onboarding is complete:

1.  **Check Running Containers:**
    ```bash
    docker ps
    ```
    You should see `wesendit-node` listed with `Status` as `Up`.

2.  **View Logs:**
    To see the real-time logs from the node container:
    ```bash
    docker logs wesendit-node -f
    ```
    Press `Ctrl+C` to stop following the logs. Look for confirmation that the node is running correctly and connected.

3.  **Use the Check Script (`node_check.sh`):**
    This script helps verify requirements and connectivity post-onboarding.
    * Make it executable (run once):
        ```bash
        chmod +x node_check.sh
        ```
    * Run the checks:
        ```bash
        sudo ./node_check.sh
        ```
        *(Running with `sudo` is often recommended for accuracy).*
    * **Useful Options:**
        * `./node_check.sh --help`: Show all available options.
        * `./node_check.sh --test <test_name>`: Run only a specific test (e.g., `--test docker`, `--test master-port`).
        * `./node_check.sh --verbose`: Show more detailed output during checks.

    ### Example Output

    **Standard Run:**
    ```bash
    sudo ./node_check.sh 
    ```
    ```
    ✅ CPU cores meet recommended specs
    ✅ CPU speed meets recommended specs
    ⚠️ Available storage meets minimum but not recommended specs
    ✅ Download speed meets recommended specs
    ✅ Upload speed meets recommended specs
    ✅ WeSendit Node container 'wesendit-node' is RUNNING (For: 21 hours ago, Restarts: 0)
    ✅ Ping latency meets recommended specs
    TCP Port 41631 (Master node) from Internet: ✅ OPEN
    TCP Port 41630 (Storage node) locally: ✅ OPEN

    === SUMMARY REPORT ===
    +----------------------+---------------+------------------+
    | Component            | Status        | Details          |
    +----------------------+---------------+------------------+
    | CPU                  | OPTIMAL       |         12 cores |
    | Storage              | ADEQUATE      |   97GB available |
    | Network Latency      | OPTIMAL       |         20.780ms |
    | WeSendit Node Docker | RUNNING       |     21 hours ago |
    | Master Port (41631)  | OPEN          |                  |
    | Storage Port (41630) | OPEN          |                  |
    +----------------------+---------------+------------------+
    Measured Bandwidth: 2349.18↓ / 2351.07↑ Mbps

    RECOMMENDATION:
    ⚠️ Meets minimums, but not optimal: Storage(A)
       Consider addressing ADEQUATE (A), STOPPED (S), WARNING (W) or other non-optimal components.

    ```

    **Verbose Run (`--verbose` or `-v`):**
    ```bash
    sudo ./node_check.sh -v
    ```
    ```
    Checking dependencies...
    Dependencies check passed.


    === Node Port Configuration Check - 2025-04-17 17:51:39 ===

    Public IP: xxx.xxx.xxx.xxx


    === System Requirements Check ===

    Checking CPU requirements...
    CPU Model: 12th Gen Intel(R) Core(TM) i5-1235U
    CPU Cores: 12 (Minimum: 2, Recommended: 2)
    CPU Speed: 4.4GHz (Minimum: 1.5GHz, Recommended: 1.5GHz)
    CPU Architecture: x86_64 - PASSED
    ✅ CPU cores meet recommended specs
    ✅ CPU speed meets recommended specs

    Checking storage requirements...
    Available Storage: 97GB (Minimum: 10GB, Recommended: 1024GB)
    ⚠️ Available storage meets minimum but not recommended specs

    Checking bandwidth requirements...
    Using Ookla speedtest...
    Download Speed: 2344.33 Mbps (Min: 10, Rec: 100)
    Upload Speed:   2118.42 Mbps (Min: 10, Rec: 100)
    ✅ Download speed meets recommended specs
    ✅ Upload speed meets recommended specs

    Checking WeSendit Node Docker status...
    ✅ WeSendit Node container 'wesendit-node' is RUNNING (For: 21 hours ago, Restarts: 0)

    === System Requirements Check Completed ===

    NETWORK LATENCY TEST
    Testing connection to network server (e.g., mst-eu1.wsi-sns.network)...
    Performing ping test...
    Pinging mst-eu1.wsi-sns.network (5 times)...
    Average ping latency to mst-eu1.wsi-sns.network: 20.689ms
    Ping latency requirements: Minimum: <150ms, Recommended: <50ms
    ✅ Ping latency meets recommended specs


    MASTER NODE PORT (TCP 41631)
    Status: Must be open externally for Master Node connection.

    Checking firewall status for port 41631 (in)...
    Firewall (iptables): No simple ACCEPT rule found for 41631/tcp in INPUT chain
    Testing TCP Port 41631 (Master node) from Internet...
    TCP Port 41631 (Master node) from Internet: ✅ OPEN


    STORAGE NODE PORT (TCP 41630)
    Status: Local connection check for dashboard/onboarding.

    Checking firewall status for port 41630 (in)...
    Firewall (iptables): No simple ACCEPT rule found for 41630/tcp in INPUT chain
    Testing TCP Port 41630 (Storage node) locally...
    TCP Port 41630 (Storage node) locally: ✅ OPEN


    === Tests completed ===

    === SUMMARY REPORT ===
    +----------------------+---------------+------------------+
    | Component            | Status        | Details          |
    +----------------------+---------------+------------------+
    | CPU                  | OPTIMAL       |         12 cores |
    | Storage              | ADEQUATE      |   97GB available |
    | Network Latency      | OPTIMAL       |         20.689ms |
    | WeSendit Node Docker | RUNNING       |     21 hours ago |
    | Master Port (41631)  | OPEN          |                  |
    | Storage Port (41630) | OPEN          |                  |
    +----------------------+---------------+------------------+
    Measured Bandwidth: 2344.33↓ / 2118.42↑ Mbps

    RECOMMENDATION:
    ⚠️ Meets minimums, but not optimal: Storage(A)
       Consider addressing ADEQUATE (A), STOPPED (S), WARNING (W) or other non-optimal components.

    ```

    **Specific Test Run (`--test ping`):**
    ```bash
    sudo ./node_check.sh --verbose --test ping 
    ```
    ```
    Checking dependencies...
    Dependencies check passed.


    === Running Specific Test: ping ===

    Performing ping test...
    Pinging mst-eu1.wsi-sns.network (5 times)...
    Average ping latency to mst-eu1.wsi-sns.network: 20.707ms
    Ping latency requirements: Minimum: <150ms, Recommended: <50ms
    ✅ Ping latency meets recommended specs

    === Specific Test (ping) Completed ===

    ```

## Stopping the Node

To stop the WeSendit node container:

```bash
docker-compose down