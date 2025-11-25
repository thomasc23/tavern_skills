#!/usr/bin/env Rscript
# MaxDiff Message Analysis
# Question 1: Analyze what types of messages perform better/worse
# Uses Claude API to classify messages by topic and sentiment
# Author: Claude Code
# Date: 2025-11-24

# Load required libraries
library(tidyverse)
library(ggridges)
library(httr)
library(jsonlite)

setwd("~/Dropbox/Tavern Research/")

# Read data
maxdiff <- read.csv("tavern_files/maxdiff_dummy_data.csv", stringsAsFactors = FALSE)

# Check for API key
api_key <- Sys.getenv("ANTHROPIC_API_KEY")

# ===== STEP 1: DISCOVER TOPICS =====

messages <- maxdiff$text

# Identify common themes
discovery_prompt <- sprintf("Analyze these %d political attack messages and identify the main POLICY TOPICS discussed. List 8-12 distinct topic categories.

Messages:
%s

Respond with ONLY a comma-separated list of topic names, nothing else.",
  length(messages),
  paste(sprintf("%d. %s", 1:length(messages), messages), collapse = "\n\n")
)

discovery_response <- POST(
  url = "https://api.anthropic.com/v1/messages",
  add_headers(
    "x-api-key" = api_key,
    "anthropic-version" = "2023-06-01",
    "content-type" = "application/json"
  ),
  body = toJSON(list(
    model = "claude-sonnet-4-5-20250929",
    max_tokens = 500,
    messages = list(
      list(
        role = "user",
        content = discovery_prompt
      )
    )
  ), auto_unbox = TRUE),
  encode = "json"
)

result <- content(discovery_response, as = "parsed")
topics_text <- result$content[[1]]$text
TOPICS <- trimws(unlist(strsplit(topics_text, ",")))

cat(paste("-", TOPICS, collapse = "\n"), "\n")

# ===== STEP 2: CLASSIFY MESSAGES =====

# Function to classify a single message
classify_message <- function(text, topics, api_key) {

  prompt <- sprintf("Analyze this political message and provide:
1. PRIMARY TOPIC (choose the best fit from: %s)
2. SECONDARY TOPIC (if applicable, otherwise 'None')
3. ATTACK INTENSITY (1-5 scale: 1=factual/mild, 5=very strong attack/alarmist)
4. SPECIFIC POLICY mentioned (brief phrase)

Message: \"%s\"

Respond in exactly this format:
PRIMARY: [topic]
SECONDARY: [topic or None]
INTENSITY: [number]
POLICY: [phrase]",
    paste(topics, collapse = ", "),
    text)

  response <- POST(
    url = "https://api.anthropic.com/v1/messages",
    add_headers(
      "x-api-key" = api_key,
      "anthropic-version" = "2023-06-01",
      "content-type" = "application/json"
    ),
    body = toJSON(list(
      model = "claude-3-5-haiku-20241022",
      max_tokens = 300,
      messages = list(
        list(
          role = "user",
          content = prompt
        )
      )
    ), auto_unbox = TRUE),
    encode = "json"
  )

  if (status_code(response) != 200) {
    warning(sprintf("API call failed with status %d", status_code(response)))
    return(list(primary = NA, secondary = NA, intensity = NA, policy = NA))
  }

  result <- content(response, as = "parsed")
  response_text <- result$content[[1]]$text

  # Parse response with more flexible regex
  primary <- str_match(response_text, "PRIMARY:\\s*(.+?)(?:\\n|$)")[,2]
  secondary <- str_match(response_text, "SECONDARY:\\s*(.+?)(?:\\n|$)")[,2]
  intensity <- as.numeric(str_match(response_text, "INTENSITY:\\s*(\\d)")[,2])
  policy <- str_match(response_text, "POLICY:\\s*(.+?)(?:\\n|$)")[,2]

  return(list(
    primary = trimws(primary),
    secondary = trimws(secondary),
    intensity = intensity,
    policy = trimws(policy)
  ))
}

# Classify messages
classifications <- vector("list", nrow(maxdiff))

for (i in 1:nrow(maxdiff)) {
  if (i %% 10 == 0) cat(sprintf("  Progress: %d/%d messages classified\n", i, nrow(maxdiff)))

  classifications[[i]] <- classify_message(maxdiff$text[i], TOPICS, api_key)

  # Rate limiting
  Sys.sleep(0.5)
}

# Convert to dataframe and combine
classification_df <- bind_rows(classifications)
maxdiff_classified <- bind_cols(maxdiff, classification_df)

# Save results
write.csv(maxdiff_classified,
          "output/maxdiff_classified.csv",
          row.names = FALSE)


# ===== STEP 3: ANALYSIS =====

# 1. Topic performance
topic_performance <- maxdiff_classified %>%
  filter(!is.na(primary)) %>%
  group_by(primary) %>%
  summarise(
    n_messages = n(),
    mean_score = mean(maxdiff_mean, na.rm = TRUE),
    sd_score = sd(maxdiff_mean, na.rm = TRUE),
    min_score = min(maxdiff_mean, na.rm = TRUE),
    max_score = max(maxdiff_mean, na.rm = TRUE)
  ) %>%
  arrange(desc(mean_score))

print(topic_performance, n = 20)

# 2. Attack intensity analysis
intensity_analysis <- maxdiff_classified %>%
  filter(!is.na(intensity)) %>%
  group_by(intensity) %>%
  summarise(
    n_messages = n(),
    mean_score = mean(maxdiff_mean, na.rm = TRUE),
    median_score = median(maxdiff_mean, na.rm = TRUE)
  ) %>%
  arrange(intensity)

print(intensity_analysis)

if (sum(!is.na(maxdiff_classified$intensity)) > 10) {
  cor_result <- cor.test(maxdiff_classified$maxdiff_mean,
                         maxdiff_classified$intensity,
                         use = "complete.obs")
  cat(sprintf("\n   Correlation: r = %.3f, p = %.4f\n",
              cor_result$estimate, cor_result$p.value))
}

# 3. Best and worst messages
top5 <- maxdiff_classified %>%
  arrange(desc(maxdiff_mean)) %>%
  head(5) %>%
  select(video_id, maxdiff_mean, primary, intensity, policy)

for (i in 1:nrow(top5)) {
  cat(sprintf("   %d. Score: %.3f | Topic: %s | Intensity: %d\n",
              i, top5$maxdiff_mean[i], top5$primary[i], top5$intensity[i]))
  cat(sprintf("      Policy: %s\n\n", top5$policy[i]))
}

bottom5 <- maxdiff_classified %>%
  arrange(maxdiff_mean) %>%
  head(5) %>%
  select(video_id, maxdiff_mean, primary, intensity, policy)

for (i in 1:nrow(bottom5)) {
  cat(sprintf("   %d. Score: %.3f | Topic: %s | Intensity: %d\n",
              i, bottom5$maxdiff_mean[i], bottom5$primary[i], bottom5$intensity[i]))
  cat(sprintf("      Policy: %s\n\n", bottom5$policy[i]))
}

# ===== STEP 4: VISUALIZATIONS =====

dir.create("figures", showWarnings = FALSE)

# Plot 1: Topic performance
p1 <- ggplot(maxdiff_classified %>% filter(!is.na(primary)),
             aes(x = reorder(primary, maxdiff_mean, median), y = maxdiff_mean)) +
  geom_boxplot(fill = "steelblue", alpha = 0.7) +
  coord_flip() +
  labs(
    title = "Message Persuasiveness by Topic",
    subtitle = "MaxDiff scores from pairwise message testing",
    x = NULL,
    y = "MaxDiff Score (Higher = More Persuasive)"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray40")
  )

ggsave("figures/fig1_topic_performance.png", p1, width = 10, height = 7, dpi = 300)

# Plot 2: Intensity analysis
p2 <- ggplot(maxdiff_classified %>% filter(!is.na(intensity)),
             aes(x = factor(intensity), y = maxdiff_mean)) +
  geom_boxplot(fill = "coral", alpha = 0.7) +
  geom_jitter(alpha = 0.2, width = 0.15, size = 1.5) +
  labs(
    title = "Attack Intensity vs. Persuasiveness",
    subtitle = "Does stronger/more alarmist messaging work better?",
    x = "Attack Intensity (1=Mild/Factual, 5=Very Strong/Alarmist)",
    y = "MaxDiff Score"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray40")
  )

ggsave("figures/fig2_intensity_analysis.png", p2, width = 9, height = 6, dpi = 300)


