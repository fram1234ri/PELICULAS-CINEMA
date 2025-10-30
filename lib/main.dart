import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String tmdbApiKey = "68c65f0480753e37bce8c54439c4e464";

// URL base para las imágenes
const String tmdbImageBaseUrl = "https://image.tmdb.org/t/p/w500";

// ---
// 1. MODELO DE DATOS
// ---
class Movie {
  final int id;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final double voteAverage;
  final String releaseDate;
  final List<int> genreIds; // Usaremos esto para mostrar géneros

  Movie({
    required this.id,
    required this.title,
    required this.overview,
    this.posterPath,
    this.backdropPath,
    required this.voteAverage,
    required this.releaseDate,
    required this.genreIds,
  });

  // Constructor para crear 'Movie' desde un JSON de la API
  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'Sin Título',
      overview: json['overview'] ?? 'Sin Sinopsis',
      posterPath: json['poster_path'],
      backdropPath: json['backdrop_path'],
      voteAverage: (json['vote_average'] as num).toDouble(),
      releaseDate: json['release_date'] ?? 'Fecha Desconocida',
      // Los IDs de género vienen como una lista de 'dynamic' (int)
      genreIds: List<int>.from(json['genre_ids'] ?? []),
    );
  }

  // Método para convertir 'Movie' de nuevo a JSON (para guardar en favoritos)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'overview': overview,
      'poster_path': posterPath,
      'backdrop_path': backdropPath,
      'vote_average': voteAverage,
      'release_date': releaseDate,
      'genre_ids': genreIds,
    };
  }

  // --- Helpers de URL de Imágenes ---
  String get fullPosterUrl {
    if (posterPath != null) {
      return '$tmdbImageBaseUrl$posterPath';
    }
    return 'https://placehold.co/500x750/333/FFF?text=Sin+Imagen';
  }

  String get fullBackdropUrl {
    if (backdropPath != null) {
      return '$tmdbImageBaseUrl$backdropPath';
    }
    // Si no hay backdrop, usa el póster
    if (posterPath != null) {
      return '$tmdbImageBaseUrl$posterPath';
    }
    return 'https://placehold.co/780x439/333/FFF?text=Sin+Imagen';
  }
}

// ---
// 2. SERVICIO DE API (Lógica de TMDB)
// ---
class ApiService {
  final String _baseUrl = "https://api.themoviedb.org/3";

  // Validador de API Key
  bool _validateApiKey() {
    if (tmdbApiKey == "TU_API_KEY_VA_AQUI" || tmdbApiKey.isEmpty) {
      // Lanza una excepción que podemos capturar en la UI
      throw Exception("API Key no encontrada. Reemplaza 'TU_API_KEY_VA_AQUI' en el código.");
    }
    return true;
  }

  // Obtener películas populares
  Future<List<Movie>> getPopularMovies() async {
    _validateApiKey();
    final url = Uri.parse('$_baseUrl/movie/popular?api_key=$tmdbApiKey&language=es-ES&page=1');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['results'];
        return results.map((json) => Movie.fromJson(json)).toList();
      } else {
        throw Exception("Error al cargar populares: ${response.reasonPhrase}");
      }
    } catch (e) {
      // Re-lanza la excepción para que el FutureBuilder la maneje
      throw Exception("Error de conexión: $e");
    }
  }

  // Buscar películas
  Future<List<Movie>> searchMovies(String query) async {
    if (query.isEmpty) return []; // No buscar si no hay texto
    _validateApiKey();
    final url = Uri.parse('$_baseUrl/search/movie?api_key=$tmdbApiKey&language=es-ES&query=$query&page=1');
    
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List results = data['results'];
        return results.map((json) => Movie.fromJson(json)).toList();
      } else {
        throw Exception("Error en la búsqueda: ${response.reasonPhrase}");
      }
    } catch (e) {
      throw Exception("Error de conexión: $e");
    }
  }
}

// ---
// 3. MANEJO DE ESTADO (Provider para Favoritos)
// ---
class FavoriteProvider extends ChangeNotifier {
  final List<Movie> _favorites = [];
  late SharedPreferences _prefs;
  bool _isInitialized = false;

  List<Movie> get favorites => _favorites;
  bool get isInitialized => _isInitialized;

  FavoriteProvider() {
    _init();
  }

  // Inicializar y cargar favoritos desde SharedPreferences
  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Obtener la lista de JSONs (guardados como strings)
    final favoriteStrings = _prefs.getStringList('favorites') ?? [];
    
    // Convertir cada string JSON de nuevo a un objeto Movie
    _favorites.clear();
    for (String movieString in favoriteStrings) {
      _favorites.add(Movie.fromJson(jsonDecode(movieString)));
    }
    
    _isInitialized = true;
    notifyListeners();
  }

  // Método para guardar la lista actual de favoritos en SharedPreferences
  Future<void> _saveFavorites() async {
    // Convertir la lista de Movie a una lista de Strings (JSON)
    final favoriteStrings = _favorites.map((movie) => jsonEncode(movie.toJson())).toList();
    await _prefs.setStringList('favorites', favoriteStrings);
  }

  // Verificar si una película ya es favorita
  bool isFavorite(Movie movie) {
    return _favorites.any((fav) => fav.id == movie.id);
  }

  // Añadir o quitar de favoritos
  void toggleFavorite(Movie movie) {
    if (isFavorite(movie)) {
      // Quitar de favoritos
      _favorites.removeWhere((fav) => fav.id == movie.id);
    } else {
      // Añadir a favoritos
      _favorites.add(movie);
    }
    // Guardar y notificar a los widgets que escuchan
    _saveFavorites();
    notifyListeners();
  }
}


// ---
// 4. PUNTO DE ENTRADA PRINCIPAL (main)
// ---
void main() {
  runApp(
    // Envolvemos la App con el Provider para que esté disponible
    // en todo el árbol de widgets.
    ChangeNotifierProvider(
      create: (context) => FavoriteProvider(),
      child: const MovieApp(),
    ),
  );
}

// ---
// 5. WIDGET DE APLICACIÓN (MaterialApp)
// ---
class MovieApp extends StatelessWidget {
  const MovieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App de Películas',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: const Color(0xFF121212), // Fondo oscuro
        cardColor: const Color(0xFF1E1E1E), // Color de tarjetas
      ),
      home: const MainScreen(),
    );
  }
}

// ---
// 6. PANTALLA CONTENEDORA (Con BottomNavigationBar)
// ---
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // Índice de la pestaña actual

  // Instancia del servicio de API
  final ApiService _apiService = ApiService();

  // Lista de las 3 pantallas principales
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    // Creamos las páginas y les pasamos el servicio de API
    _pages = [
      PopularMoviesPage(apiService: _apiService),
      SearchMoviesPage(apiService: _apiService),
      const FavoritesMoviesPage(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.movie),
            label: 'Populares',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Buscar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Favoritos',
          ),
        ],
      ),
    );
  }
}

// ---
// 7. PANTALLA 1: PELÍCULAS POPULARES
// ---
class PopularMoviesPage extends StatefulWidget {
  final ApiService apiService;
  const PopularMoviesPage({super.key, required this.apiService});

  @override
  State<PopularMoviesPage> createState() => _PopularMoviesPageState();
}

class _PopularMoviesPageState extends State<PopularMoviesPage> 
    with AutomaticKeepAliveClientMixin {

  // Usamos un Future para manejar el estado de la llamada a la API
  late Future<List<Movie>> _popularMoviesFuture;

  @override
  void initState() {
    super.initState();
    _popularMoviesFuture = widget.apiService.getPopularMovies();
  }
  
  // Recargar la data
  Future<void> _refresh() async {
    setState(() {
      _popularMoviesFuture = widget.apiService.getPopularMovies();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Necesario para AutomaticKeepAliveClientMixin
    return Scaffold(
      appBar: AppBar(
        title: const Text('Películas Populares'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          )
        ],
      ),
      body: FutureBuilder<List<Movie>>(
        future: _popularMoviesFuture,
        builder: (context, snapshot) {
          // Estado de Carga
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // Estado de Error
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  "Error: ${snapshot.error}", 
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Estado Exitoso
          if (snapshot.hasData) {
            final movies = snapshot.data!;
            if (movies.isEmpty) {
              return const Center(child: Text("No se encontraron películas."));
            }
            // Usamos un GridView para la vista de pósters
            return RefreshIndicator(
              onRefresh: _refresh,
              child: MovieGridView(movies: movies),
            );
          }
          // Estado por defecto (no debería pasar)
          return const Center(child: Text("Iniciando..."));
        },
      ),
    );
  }

  // Mantenemos viva la pestaña para no perder el estado
  @override
  bool get wantKeepAlive => true;
}

// ---
// 8. PANTALLA 2: BÚSQUEDA DE PELÍCULAS
// ---
class SearchMoviesPage extends StatefulWidget {
  final ApiService apiService;
  const SearchMoviesPage({super.key, required this.apiService});

  @override
  State<SearchMoviesPage> createState() => _SearchMoviesPageState();
}

class _SearchMoviesPageState extends State<SearchMoviesPage>
    with AutomaticKeepAliveClientMixin {
      
  final TextEditingController _searchController = TextEditingController();
  List<Movie> _searchResults = [];
  bool _isLoading = false;
  String _errorMessage = "";
  // Timer para "debounce" (no buscar en cada letra, sino esperar un momento)
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    // Si hay un timer activo, cancelarlo
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // Empezar un nuevo timer de 500ms
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isNotEmpty) {
        setState(() {
          _isLoading = true;
          _errorMessage = "";
        });
        try {
          final results = await widget.apiService.searchMovies(query);
          setState(() {
            _searchResults = results;
            _isLoading = false;
          });
        } catch (e) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.toString();
            _searchResults = [];
          });
        }
      } else {
        // Limpiar resultados si la búsqueda está vacía
        setState(() {
          _searchResults = [];
          _isLoading = false;
          _errorMessage = "";
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Necesario para KeepAlive
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buscar Películas'),
      ),
      body: Column(
        children: [
          // Barra de Búsqueda
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Escribe el nombre de una película...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.0),
                ),
                filled: true,
              ),
            ),
          ),
          // Resultados
          Expanded(
            child: _buildResultsBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Text(
            "Error: $_errorMessage", 
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      // Si no hay búsqueda, mostrar un ícono
      if (_searchController.text.isEmpty) {
        return const Center(child: Icon(Icons.search_off_outlined, size: 60, color: Colors.grey));
      } else {
        return const Center(child: Text("No se encontraron resultados."));
      }
    }
    // Si hay resultados, mostrar la lista
    // Usamos MovieGridView para reusar el widget
    return MovieGridView(movies: _searchResults);
  }

  @override
  bool get wantKeepAlive => true;
}

// ---
// 9. PANTALLA 3: FAVORITOS
// ---
class FavoritesMoviesPage extends StatefulWidget {
  const FavoritesMoviesPage({super.key});

  @override
  State<FavoritesMoviesPage> createState() => _FavoritesMoviesPageState();
}

class _FavoritesMoviesPageState extends State<FavoritesMoviesPage>
    with AutomaticKeepAliveClientMixin {
      
  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Escuchamos los cambios en el FavoriteProvider
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Favoritos'),
      ),
      body: Consumer<FavoriteProvider>(
        builder: (context, provider, child) {
          
          // Esperar a que los favoritos se carguen de SharedPreferences
          if (!provider.isInitialized) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.favorites.isEmpty) {
            return const Center(
              child: Text(
                'No tienes películas favoritas.\n¡Añade algunas!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          
          // Mostrar la lista de favoritos
          return MovieGridView(movies: provider.favorites);
        },
      ),
    );
  }
  
  @override
  bool get wantKeepAlive => true;
}

// ---
// 10. PANTALLA DE DETALLE (Se navega a esta)
// ---
class DetailScreen extends StatelessWidget {
  final Movie movie;

  const DetailScreen({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Usamos CustomScrollView para tener un AppBar colapsable
      body: CustomScrollView(
        slivers: [
          // AppBar con la imagen de fondo
          SliverAppBar(
            expandedHeight: 250.0,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                movie.title, 
                style: const TextStyle(shadows: [Shadow(blurRadius: 10.0, color: Colors.black)]),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    movie.fullBackdropUrl,
                    fit: BoxFit.cover,
                  ),
                  // Gradiente oscuro para que el texto resalte
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Botón de Favorito en el AppBar
            actions: [
              // Usamos un Consumer para que el botón se actualice
              // solo cuando cambia el estado de favoritos.
              Consumer<FavoriteProvider>(
                builder: (context, provider, child) {
                  final bool isFav = provider.isFavorite(movie);
                  return IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? Colors.red : Colors.white,
                      size: 30,
                    ),
                    onPressed: () {
                      // Llamamos al provider para cambiar el estado
                      provider.toggleFavorite(movie);
                    },
                  );
                },
              ),
            ],
          ),
          // Contenido de la película
          SliverList(
            delegate: SliverChildListDelegate([
              // Sección de Título y Puntuación
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.yellow, size: 20),
                        const SizedBox(width: 5),
                        Text(
                          movie.voteAverage.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 18),
                        ),
                        const SizedBox(width: 20),
                        const Icon(Icons.calendar_today, color: Colors.grey, size: 16),
                        const SizedBox(width: 5),
                        Text(
                          movie.releaseDate,
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Línea divisora
                    const Divider(),
                    const SizedBox(height: 16),
                    // Sinopsis
                    Text(
                      'Sinopsis',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      movie.overview.isNotEmpty ? movie.overview : "Sinopsis no disponible.",
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}


// ---
// 11. WIDGET REUTILIZABLE: Grid de Películas
// ---
class MovieGridView extends StatelessWidget {
  final List<Movie> movies;

  const MovieGridView({super.key, required this.movies});

  @override
  Widget build(BuildContext context) {
    // GridView para mostrar los pósters
    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      // Cuántos elementos por fila
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, // 2 películas por fila
        childAspectRatio: 0.68, // Proporción del póster
        mainAxisSpacing: 8.0,
        crossAxisSpacing: 8.0,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];
        return MoviePosterCard(movie: movie);
      },
    );
  }
}

// ---
// 12. WIDGET REUTILIZABLE: Tarjeta de Póster
// ---
class MoviePosterCard extends StatelessWidget {
  final Movie movie;
  const MoviePosterCard({super.key, required this.movie});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias, // Recortar la imagen
      elevation: 5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () {
          // Navegar a la pantalla de detalle
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DetailScreen(movie: movie),
            ),
          );
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Imagen de fondo (el póster)
            Image.network(
              movie.fullPosterUrl,
              fit: BoxFit.cover,
              // Placeholder mientras carga
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(child: CircularProgressIndicator.adaptive());
              },
              // Error si no carga la imagen
              errorBuilder: (context, error, stackTrace) {
                return const Center(child: Icon(Icons.movie_filter_outlined, color: Colors.grey));
              },
            ),
            // Gradiente inferior para el texto
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 80,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black, Colors.transparent],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    movie.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            // Puntuación en la esquina superior
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.yellow, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      movie.voteAverage.toStringAsFixed(1),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
