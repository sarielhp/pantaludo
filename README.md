# Pantaludo (Pantaludounboundiglossia)

[**Play the Game Online!**](https://sarielhp.github.io/pantaludo/)

Pantaludo is an interactive, Wordle-style word guessing game that supports words of any length. It features both a command-line interface and a modern web-based UI.

## Features

- **Any Word Length:** Unlike traditional Wordle, Pantaludo supports guessing words of various lengths.
- **Intelligent Word Selection:** Uses prefix-free analysis on word frequency data to select targets that are distinct and commonly used.
- **Multiple Interfaces:**
  - **Web Play:** A modern, responsive web interface with visual history and a virtual keyboard.
  - **CLI Play:** A text-based version of the game playable directly in your terminal.
- **Advanced Word Analysis:** Includes tools for preprocessing large word lists, performing Trie-based prefix analysis, and exporting optimized datasets for the web.

## Project Structure

- `word_analyzer.jl`: The main Julia script containing the game logic, data processing pipelines, and web server.
- `index.html`: The frontend for the web-based game.
- `data/`: Directory for raw word frequency data and dictionary files.
- `output/`: Directory for processed datasets and JSON exports used by the web interface.

## How to Run

### Web Game (Local)
To start a local web server for the game:
```bash
./word_analyzer.jl wplay
```
Then navigate to `http://127.0.0.1:8080` in your browser.

### CLI Game
To play the game directly in your terminal:
```bash
./word_analyzer.jl play
```

### Data Pipeline
To rebuild the web data bundle from raw frequency files:
```bash
./word_analyzer.jl deploy
```

## Commands
Run `./word_analyzer.jl help` to see a full list of available commands, including:
- `preprocess`: Filter raw word frequency files.
- `prefix_free`: Extract a prefix-free subset of words.
- `wexport`: Create optimized JSON data for the web.
- `zip`: Package the application for deployment.

## License
This project is for educational and entertainment purposes.
