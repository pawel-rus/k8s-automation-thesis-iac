from app import create_app

app = create_app()

if __name__ == "__main__":
    print("Starting Flask app...")  # <-- dodaj to na start
    app.run(host="0.0.0.0", port=5000)

