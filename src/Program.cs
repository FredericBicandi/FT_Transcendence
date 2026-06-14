using System.Collections.Concurrent;

var builder = WebApplication.CreateBuilder(args);

var supabaseUrl =
    builder.Configuration["Supabase:Url"] ??
    builder.Configuration["NEXT_PUBLIC_SUPABASE_URL"];
var supabasePublishableKey =
    builder.Configuration["Supabase:PublishableKey"] ??
    builder.Configuration["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"];

if (string.IsNullOrWhiteSpace(supabaseUrl) ||
    string.IsNullOrWhiteSpace(supabasePublishableKey))
{
    throw new InvalidOperationException(
        "Missing Supabase configuration. Set Supabase__Url and " +
        "Supabase__PublishableKey."
    );
}

builder.Services.AddSingleton<
    ConcurrentDictionary<string, ClientConnection>
>();
builder.Services.AddHttpClient();
builder.Services.AddSingleton<IMatchRepository, SupabaseMatchRepository>();
builder.Services.AddSingleton<Ws>();
builder.Services.AddSingleton<DashboardWebSocketHub>();

var app = builder.Build();
var webSocketApp = app.Services.GetRequiredService<Ws>();
var dashboardWebSocketApp =
    app.Services.GetRequiredService<DashboardWebSocketHub>();

app.UseHttpsRedirection();
app.UseWebSockets();

app.Map("/ws/dashboard", dashboardWebSocketApp.RunWebSocketApp);
app.Map("/ws", webSocketApp.RunWebSocketApp);

app.Run();
