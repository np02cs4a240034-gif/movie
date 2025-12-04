const API_URL = 'movies.json';   // FIXED — NO MORE /movies

const movieListDiv = document.getElementById('movie-list');
const searchInput = document.getElementById('search-input');
const form = document.getElementById('add-movie-form');
const formError = document.getElementById('form-error');

let allMovies = [];

function renderMovies(moviesToDisplay) {
  movieListDiv.innerHTML = '';
  if (moviesToDisplay.length === 0) {
    movieListDiv.innerHTML = '<p>No movies found matching your criteria.</p>';
    return;
  }
  moviesToDisplay.forEach(movie => {
    const movieElement = document.createElement('div');
    movieElement.classList.add('movie-item');
    movieElement.innerHTML = `
      <p><strong>${movie.title}</strong> (${movie.year}) - ${movie.genre}</p>
      <button class="btn btn-primary" onclick="editMoviePrompt(${movie.id})">Edit</button>
      <button class="btn btn-danger" onclick="deleteMovie(${movie.id})">Delete</button>
    `;
    movieListDiv.appendChild(movieElement);
  });
}

function fetchMovies() {
  fetch(API_URL)
    .then(response => response.json())
    .then(data => {
      allMovies = data.movies;
      renderMovies(allMovies);
    })
    .catch(error => {
      formError.style.display = 'block';
      formError.textContent = 'Failed to load movies: ' + error.message;
    });
}

fetchMovies();

searchInput.addEventListener('input', () => {
  const searchTerm = searchInput.value.toLowerCase();
  const filteredMovies = allMovies.filter(movie =>
    movie.title.toLowerCase().includes(searchTerm) ||
    movie.genre.toLowerCase().includes(searchTerm)
  );
  renderMovies(filteredMovies);
});

form.addEventListener('submit', function (event) {
  event.preventDefault();

  const titleVal = document.getElementById('title').value.trim();
  const genreVal = document.getElementById('genre').value.trim();
  const yearVal = parseInt(document.getElementById('year').value);

  if (!titleVal || Number.isNaN(yearVal)) {
    formError.style.display = 'block';
    formError.textContent = 'Please provide title and a valid year.';
    return;
  }

  const newMovie = {
    id: Date.now(),
    title: titleVal,
    genre: genreVal || "Unknown",
    year: yearVal
  };

  allMovies.push(newMovie);
  renderMovies(allMovies);
  this.reset();
  formError.style.display = 'none';
});

function editMoviePrompt(id) {
  const movie = allMovies.find(m => m.id === id);
  if (!movie) return;

  const newTitle = prompt("Enter new title:", movie.title);
  const newYear = parseInt(prompt("Enter new year:", movie.year));
  const newGenre = prompt("Enter new genre:", movie.genre);

  if (!newTitle || Number.isNaN(newYear) || !newGenre) return;

  movie.title = newTitle;
  movie.year = newYear;
  movie.genre = newGenre;

  renderMovies(allMovies);
}

function deleteMovie(id) {
  allMovies = allMovies.filter(movie => movie.id !== id);
  renderMovies(allMovies);
}
