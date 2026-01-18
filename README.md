# Funicular

> 🎵Funicu-lì, Funicu-là!🚊🚊🚊
>
> 🎵Funicu-lì, Funicu-là!🚞🚞🚞

Funicular is a Rails plugin that enables you to write client-side UI components in Ruby, compiled to mruby bytecode (.mrb) for efficient browser execution.

## Features

- Write client-side code in Ruby instead of JavaScript
- Automatic compilation of Ruby files to mruby bytecode (.mrb)
- Development mode with debug symbols (-g option)
- Production mode with optimized bytecode (no debug symbols)
- Auto-recompilation in development when source files change
- Seamless Rails integration
- Rails-style routing with `link_to` helper and URL path helpers
- RESTful HTTP method support (GET, POST, PUT, PATCH, DELETE)
- Built-in CSRF protection for non-GET requests

## Prerequisites

Funicular requires the `picorbc` mruby compiler to be available in your PATH.

Installation instructions:
- Install picoruby: https://github.com/picoruby/picoruby
- Or add picorbc to your PATH

## Installation

Add this line to your application's Gemfile:

```ruby
gem "funicular"
```

Then execute:

```bash
bundle install
```

## Usage

### Directory Structure

Place your Funicular application files in the following structure:

```
app/funicular/
  models/              # UI models
    user.rb
    session.rb
  components/          # UI components
    login_component.rb
    chat_component.rb
  initializer.rb       # Application initialization (optional)
```

The `initializer.rb` file (or any file ending with `_initializer.rb`) is loaded last, after all models and components. Use it for application setup code like routing configuration.

### Compilation

#### Development Mode

In development mode, Funicular automatically recompiles your Ruby files when they change. The compiled bytecode includes debug symbols (-g option).

To manually compile:

```bash
bundle exec rake funicular:compile
```

Output:
- File: `app/assets/builds/app.mrb`
- Debug mode: enabled
- Size: ~19KB (with debug symbols)

The compiled file is placed in `app/assets/builds/` so that Rails asset pipeline (Propshaft) can process it and serve it from `public/assets/` with proper cache busting.

#### Production Mode

In production mode, compile without debug symbols for smaller file size:

```bash
RAILS_ENV=production bundle exec rake funicular:compile
```

Output:
- File: `app/assets/builds/app.mrb`
- Debug mode: disabled
- Size: ~16KB (optimized)

The compilation task is automatically run before `assets:precompile` in production deployments.

### Loading in Views

Include the compiled bytecode in your view using the `asset_path` helper. If you have an `initializer.rb` file, it will execute automatically when the mrb file loads:

```erb
<div id="app"></div>

<script type="application/x-mrb" src="<%= asset_path('app.mrb') %>"></script>
```

The `asset_path` helper ensures that:
- In development: The file is served from `app/assets/builds/` via Propshaft
- In production: The file is served from `public/assets/` with a digest hash for cache busting (e.g., `application-abc123.mrb`)

Example `app/funicular/initializer.rb`:

```ruby
puts "Funicular Chat App initializing..."

# Load all model schemas before starting the app
Funicular.load_schemas({ User => "user", Session => "session", Channel => "channel" }) do
  # Start the application after all schemas are loaded
  Funicular.start(container: 'app') do |router|
    router.get('/login', to: LoginComponent, as: 'login')
    router.get('/chat/:channel_id', to: ChatComponent, as: 'chat_channel')
    router.get('/settings', to: SettingsComponent, as: 'settings')
    router.delete('/logout', to: LogoutComponent, as: 'logout')
    router.set_default('/login')
  end
end
```

### File Concatenation Order

Funicular concatenates files in the following order:

1. `app/funicular/models/**/*.rb` (alphabetically)
2. `app/funicular/components/**/*.rb` (alphabetically)
3. `app/funicular/initializer.rb` and `app/funicular/*_initializer.rb`

This ensures that:
- Model classes are defined before components that depend on them
- Components are defined before initialization code that uses them

### Routing

Funicular provides Rails-style routing with automatic URL helper generation and RESTful HTTP method support.

#### Defining Routes

Use Rails-style DSL in your `initializer.rb`:

```ruby
Funicular.start(container: 'app') do |router|
  # GET routes with URL helpers
  router.get('/login', to: LoginComponent, as: 'login')
  router.get('/users/:id', to: UserComponent, as: 'user')
  router.get('/users/:id/edit', to: EditUserComponent, as: 'edit_user')

  # RESTful routes
  router.post('/users', to: CreateUserComponent, as: 'users')
  router.patch('/users/:id', to: UpdateUserComponent, as: 'update_user')
  router.delete('/users/:id', to: DeleteUserComponent, as: 'delete_user')

  # Set default route
  router.set_default('/login')
end
```

The `as` option automatically generates URL helper methods (e.g., `login_path`, `user_path`).

#### Using URL Helpers

URL helpers are automatically available in all components:

```ruby
class UserListComponent < Funicular::Component
  def render
    div do
      # Static path
      link_to login_path do
        span { "Login" }
      end

      # Path with parameter from state/props
      state.users.each do |user|
        link_to user_path(user.id) do
          span { user.name }
        end
      end

      # Or pass model object with id method
      link_to edit_user_path(state.current_user) do
        span { "Edit Profile" }
      end
    end
  end
end
```

#### Using link_to Helper

The `link_to` helper creates navigation links with automatic routing:

```ruby
# GET navigation (uses History API)
link_to settings_path, class: "button" do
  span { "Settings" }
end

# Path with dynamic data
link_to chat_channel_path(props[:channel]) do
  div(class: "channel-name") { "# #{props[:channel].name}" }
  div(class: "channel-desc") { props[:channel].description }
end

# RESTful actions (uses Fetch API)
link_to user_path(state.user), method: :delete, class: "danger" do
  span { "Delete Account" }
end

# Supported HTTP methods: :get, :post, :put, :patch, :delete
```

#### CSRF Protection

Non-GET requests automatically include CSRF tokens from Rails meta tags:

```erb
<!-- In your Rails layout -->
<head>
  <%= csrf_meta_tags %>
</head>
```

Funicular automatically reads the CSRF token and includes it in `X-CSRF-Token` header for POST, PUT, PATCH, and DELETE requests.

#### Viewing Routes

Display all defined routes with the Rake task:

```bash
rake funicular:routes
```

Output example:

```
Method   Path                Component         Helper
----------------------------------------------------------
GET      /login              LoginComponent    login_path
GET      /chat/:channel_id   ChatComponent     chat_channel_path
GET      /settings           SettingsComponent settings_path
DELETE   /logout             LogoutComponent   logout_path

Total: 4 routes
```

#### Backward Compatibility

The old `add_route` method is still supported:

```ruby
# Old style (still works)
router.add_route('/login', LoginComponent)

# With URL helper
router.add_route('/login', LoginComponent, as: 'login')
```

## Rails Asset Pipeline Integration

Funicular integrates with Rails' asset pipeline (Propshaft) following Rails best practices:

### Directory Structure

```
app/
  funicular/                    # Source files (version controlled)
    models/
    components/
    initializer.rb
  assets/
    builds/                     # Compiled output (gitignored)
      app.mrb                   # Generated by funicular:compile
      .keep                     # Keep directory in git
```

### Development vs Production

**Development:**
- Files in `app/assets/builds/` are served directly by Propshaft
- Middleware automatically recompiles when source files change
- Debug symbols included for better error messages

**Production:**
- `rake assets:precompile` runs `funicular:compile` first
- Propshaft copies files to `public/assets/` with digest hashes
- Example: `app.mrb` -> `app-abc123def456.mrb`
- Debug symbols excluded for smaller file size

### Cache Busting

Using `asset_path('app.mrb')` in views ensures:
- Correct path resolution in all environments
- Automatic cache busting when files change
- Standard Rails asset handling

## Development Tools

### Component Debug Highlighter

Funicular provides a debug tool that visually highlights components with `data-component` attributes in development mode.

#### Installation

Run the install task to copy debug assets to your Rails app:

```bash
bundle exec rake funicular:install
```

This creates:
- `app/assets/javascripts/funicular_debug.js`
- `app/assets/stylesheets/funicular_debug.css`

#### Integration with Sprockets

Add to `app/assets/config/manifest.js`:

```javascript
//= link_directory ../javascripts .js
//= link_directory ../stylesheets .css
```

Then update your layout to load the debug assets in development only:

```erb
<head>
  <% if Rails.env.development? %>
    <%= stylesheet_link_tag "funicular_debug", "data-turbo-track": "reload" %>
    <%= javascript_include_tag "funicular_debug", "data-turbo-track": "reload" %>
  <% end %>
</head>
```

#### Features

In development mode, components automatically get `data-component` attributes with their class name. The debug tool:

- Highlights components with a green/yellow/pink/cyan outline
  ```ruby
  # in app/funicular/initializer.rb
  Funicular.debug_color = "pink"  # Options: "green", "yellow", "pink", "cyan", or nil to disable
  ```
- Shows a triangle indicator in the bottom-right corner
- Displays component name and id value (if exists) on hover
- Does not distort layout (uses `outline` instead of `border`)

This helps developers quickly identify which component class renders each part of the UI.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/hasumikin/funicular.

## License

MIT
