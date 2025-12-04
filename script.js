const API_URL = "movies.json";     

const movieListDiv = document.getElementById("movie-list");
const searchInput = document.getElementById("search-input");
const form = document.getElementById("add-movie-form");
const formError = document.getElementById("form-error");

let allMovies = [];

/* ---------------------------- */
/* Render Movie Items           */
/* ---------------------------- */
function renderMovies(moviesToDisplay) {
  movieListDiv.innerHTML = "";

  if (moviesToDisplay.length === 0) {
    movieListDiv.innerHTML = "<p>No movies found.</p>";
    return;
  }

  moviesToDisplay.forEach(movie => {
    const movieElement = document.createElement("div");
    movieElement.classList.add("movie-item");

    movieElement.innerHTML = `
      <div>
        <p><strong>${movie.title}</strong> (${movie.year})</p>
        <p style="color:var(--muted); font-size:0.9em;">${movie.genre}</p>
      </div>

      <div style="display:flex; gap:6px;">
        <button class="btn btn-primary" onclick="editMoviePrompt(${movie.id})">Edit</button>
        <button class="btn btn-danger" onclick="deleteMovie(${movie.id})">Delete</button>
      </div>
    `;

    movieListDiv.appendChild(movieElement);
  });
}

/* ---------------------------- */
/* Load movies.json             */
/* ---------------------------- */
function fetchMovies() {
  fetch(API_URL)
    .then(response => response.json())
    .then(data => {
      allMovies = data.movies;
      renderMovies(allMovies);
    })
    .catch(error => {
      formError.style.display = "block";
      formError.textContent = "Failed to load movies: " + error.message;
    });
}

fetchMovies();

/* ---------------------------- */
/* Live Search Filter           */
/* ---------------------------- */
searchInput.addEventListener("input", () => {
  const searchTerm = searchInput.value.toLowerCase();

  const filteredMovies = allMovies.filter(movie =>
    movie.title.toLowerCase().includes(searchTerm) ||
    movie.genre.toLowerCase().includes(searchTerm)
  );

  renderMovies(filteredMovies);
});

/* ---------------------------- */
/* Add Movie                    */
/* ---------------------------- */
form.addEventListener("submit", function (event) {
  event.preventDefault();

  const titleVal = document.getElementById("title").value.trim();
  const genreVal = document.getElementById("genre").value.trim();
  const yearVal = parseInt(document.getElementById("year").value);

  if (!titleVal || Number.isNaN(yearVal)) {
    formError.style.display = "block";
    formError.textContent = "Please provide a title and a valid year.";
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
  form.reset();
  formError.style.display = "none";
});

/* ---------------------------- */
/* Edit Movie                   */
/* ---------------------------- */
function editMoviePrompt(id) {
  const movie = allMovies.find(m => m.id === id);
  if (!movie) return;

  const newTitle = prompt("New title:", movie.title) || movie.title;
  const newYear = parseInt(prompt("New year:", movie.year)) || movie.year;
  const newGenre = prompt("New genre:", movie.genre) || movie.genre;

  if (Number.isNaN(newYear)) return;

  movie.title = newTitle;
  movie.year = newYear;
  movie.genre = newGenre;

  renderMovies(allMovies);
}

/* ---------------------------- */
/* Delete Movie                 */
/* ---------------------------- */
function deleteMovie(id) {
  allMovies = allMovies.filter(movie => movie.id !== id);
  renderMovies(allMovies);
}
