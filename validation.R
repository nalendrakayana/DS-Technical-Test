# 1. Setup
library(jsonlite)
library(dplyr)
library(ResourceSelection)
library(ggplot2)


data_credit <- read.csv("credit_scoring.csv")
model_recipe <- fromJSON("logistic_model_recipe.json") # Pastikan nama file JSON sudah benar

# Ekstrak model
intercept_r <- model_recipe$intercept
coeffs_r <- as.list(model_recipe$coefficients)
scaler_means_r <- as.list(model_recipe$scaling_params$mean)
scaler_sds_r <- as.list(model_recipe$scaling_params$scale)

# Feature Engineering sama persis di python
data_credit_fe <- data_credit %>%
  mutate(
    dfi_ratio = loan_amount / (monthly_income + 1e-6),
    loan_to_score_ratio = loan_amount / (credit_score + 1e-6),
    age_x_credit_score = age * credit_score,
    is_low_income = ifelse(monthly_income < quantile(monthly_income, 0.25), 1, 0),
    age_group = cut(age,
                    breaks = c(18, 30, 45, 60, Inf),
                    labels = c('Muda (18-30)', 'Dewasa (31-45)', 'Paruh Baya (46-60)', 'Senior (60+)'),
                    right = FALSE, include.lowest = TRUE)
  ) %>%
  mutate(
    # Buat kolom dummy agar cocok dengan output pd.get_dummies() di Python
    age_group_Dewasa (31-45) = ifelse(age_group == 'Dewasa (31-45)', 1, 0),
    age_group_Muda (18-30) = ifelse(age_group == 'Muda (18-30)', 1, 0),
    age_group_Paruh Baya (46-60) = ifelse(age_group == 'Paruh Baya (46-60)', 1, 0),
    age_group_Senior (60+) = ifelse(age_group == 'Senior (60+)', 1, 0)
  )

# Matriks Fitur untuk Prediksi
# Ambil nama fitur dari file json 
feature_names_from_python <- names(coeffs_r)
final_features_df <- data_credit_fe %>% select(all_of(feature_names_from_python))
X_matrix <- as.matrix(final_features_df)

# SCALING DATA DI R 
cat("Melakukan scaling pada data di R...\n")

# Identifikasi kolom yang punya parameter scaling dari Python
numeric_cols_to_scale <- names(scaler_means_r)

# Pisah matriks fitur jadi dua bagian
# Bagian yang akan scaling
X_matrix_to_scale <- X_matrix[, numeric_cols_to_scale]
# kolom dummy
X_matrix_dummies <- X_matrix[, !colnames(X_matrix) %in% numeric_cols_to_scale, drop = FALSE]

# Scaling feature (hanya feature khusus)
mean_vec <- unlist(scaler_means_r)[numeric_cols_to_scale]
sd_vec <- unlist(scaler_sds_r)[numeric_cols_to_scale]
X_matrix_scaled_part <- scale(X_matrix_to_scale, center = mean_vec, scale = sd_vec)

# Gabung lagi kedua bagian matriks
X_matrix_final <- cbind(X_matrix_scaled_part, X_matrix_dummies)

# Urut kolom biar sama persis kaya python
X_matrix_final_ordered <- X_matrix_final[, feature_names_from_python]

# Hitung Probabilitas Prediksi
coeffs_vector <- unlist(coeffs_r)[feature_names_from_python]
log_odds <- intercept_r + (X_matrix_scaled %*% coeffs_vector)
probabilities <- 1 / (1 + exp(-log_odds))
data_credit_fe$predicted_prob <- as.numeric(probabilities)

# Show Hasil Hosmer-Lemeshow Test
print("--- Hasil Hosmer-Lemeshow Test ---")
hl_test_result <- hoslem.test(x = data_credit_fe$default, y = data_credit_fe$predicted_prob, g = 10)
print(hl_test_result)

# Simpan Calibration Curve
print("--- Make and Save Calibration Curve ---")
calibration_data <- data_credit_fe %>%
  mutate(prob_bin = ntile(predicted_prob, 10)) %>%
  group_by(prob_bin) %>%
  summarise(
    mean_predicted_prob = mean(predicted_prob),
    mean_actual_default = mean(default)
  )

calibration_plot <- ggplot(calibration_data, aes(x = mean_predicted_prob, y = mean_actual_default)) +
  geom_abline(linetype = "dashed", color = "red", size = 1) +
  geom_line(color = "blue", size = 1.2) +
  geom_point(color = "blue", size = 4) +
  labs(
    title = "Calibration Curve - Logistic Regression",
    subtitle = "Perbandingan Prediksi Probabilitas dengan Realita",
    x = "Rata-rata Prediksi Probabilitas Gagal Bayar",
    y = "Rata-rata Aktual Gagal Bayar"
  ) +
  coord_cartesian(xlim = c(0, 1), ylim = c(0, 1)) +
  theme_minimal()

# Simpan plot 
ggsave("calibration_curve.png", plot = calibration_plot, width = 8, height = 6, dpi = 150)
print("Plot 'calibration_curve.png' berhasil disimpan.")