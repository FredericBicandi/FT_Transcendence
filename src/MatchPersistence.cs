using System.Net.Http.Headers;
using System.Net.Http.Json;

public sealed record MatchRecord(
    Guid Id,
    DateTimeOffset StartedAt,
    DateTimeOffset EndedAt,
    int DurationSeconds
);

public interface IMatchRepository
{
    Task SaveAsync(
        MatchRecord match,
        CancellationToken cancellationToken = default
    );
}

public sealed class SupabaseMatchRepository : IMatchRepository
{
    private readonly IHttpClientFactory httpClientFactory;
    private readonly string? publishableKey;
    private readonly string? supabaseUrl;

    public SupabaseMatchRepository(
        IHttpClientFactory httpClientFactory,
        IConfiguration configuration
    )
    {
        this.httpClientFactory = httpClientFactory;
        supabaseUrl =
            configuration["Supabase:Url"] ??
            configuration["NEXT_PUBLIC_SUPABASE_URL"];
        publishableKey =
            configuration["Supabase:PublishableKey"] ??
            configuration["NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"];
    }

    public async Task SaveAsync(
        MatchRecord match,
        CancellationToken cancellationToken = default
    )
    {
        if (string.IsNullOrWhiteSpace(supabaseUrl) ||
            string.IsNullOrWhiteSpace(publishableKey))
        {
            throw new InvalidOperationException(
                "Supabase URL and publishable key are required."
            );
        }

        var endpoint = new Uri(
            new Uri(EnsureTrailingSlash(supabaseUrl)),
            "rest/v1/matches"
        );
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Add("apikey", publishableKey);

        // Legacy anon keys are JWTs. New sb_publishable_* keys belong only in
        // the apikey header; sending them as Bearer tokens causes a 401.
        if (publishableKey.StartsWith("eyJ", StringComparison.Ordinal))
        {
            request.Headers.Authorization =
                new AuthenticationHeaderValue("Bearer", publishableKey);
        }

        request.Headers.Add("Prefer", "return=minimal");
        request.Content = JsonContent.Create(new
        {
            id = match.Id,
            started_at = match.StartedAt,
            ended_at = match.EndedAt,
            duration_seconds = match.DurationSeconds
        });

        using var response = await httpClientFactory.CreateClient().SendAsync(
            request,
            cancellationToken
        );

        if (!response.IsSuccessStatusCode)
        {
            var responseBody = await response.Content.ReadAsStringAsync(
                cancellationToken
            );
            throw new HttpRequestException(
                $"Supabase match insert failed ({(int)response.StatusCode} " +
                $"{response.ReasonPhrase}): {responseBody}"
            );
        }
    }

    private static string EnsureTrailingSlash(string value) =>
        value.EndsWith('/') ? value : $"{value}/";
}

internal sealed class NullMatchRepository : IMatchRepository
{
    public static NullMatchRepository Instance { get; } = new();

    public Task SaveAsync(
        MatchRecord match,
        CancellationToken cancellationToken = default
    ) =>
        Task.CompletedTask;
}
