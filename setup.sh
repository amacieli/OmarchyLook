#!/bin/bash
# Setup script for omarchy-look development environment

set -e

echo "📦 Setting up omarchy-look development environment..."

# Check Python version
if ! python3 --version &>/dev/null; then
    echo "Error: Python 3 is required"
    exit 1
fi

# Create virtual environment
if [ ! -d ".venv" ]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

# Activate venv
source .venv/bin/activate || . .venv/Scripts/activate

# Upgrade pip
echo "Upgrading pip..."
pip install --upgrade pip

# Install dependencies
echo "Installing dependencies..."
pip install -e .

# Copy .env.example to .env if not present
if [ ! -f ".env" ]; then
    echo "Creating .env from template..."
    cp .env.example .env
    echo ""
    echo "⚠️  Edit .env with your Azure App Registration credentials:"
    echo "    AZURE_CLIENT_ID=your_client_id_here"
    echo "    AZURE_TENANT_ID=your_tenant_id_here"
    echo ""
fi

echo "✅ Setup complete!"
echo ""
echo "To activate the environment, run:"
echo "  source .venv/bin/activate  # or .venv\\Scripts\\activate on Windows"
echo ""
echo "To start the app, run:"
echo "  python main.py"
