import Foundation

/// Closed packaging taxonomy (mirrors moderation-service `topics.rs`).
struct ContentCategory: Equatable, Sendable, Identifiable, Hashable {
    let id: String
    let subcategories: [String]

    var displayName: String {
        id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func subcategoryDisplayName(_ subcategory: String) -> String {
        subcategory.replacingOccurrences(of: "_", with: " ").capitalized
    }

    static let all: [ContentCategory] = [
        ContentCategory(id: "sports", subcategories: [
            "football_soccer", "basketball", "american_football", "baseball", "ice_hockey",
            "tennis", "combat_sports", "motorsport", "cycling", "athletics", "winter_sports",
            "water_sports", "golf", "volleyball", "esports", "extreme_sports", "sports_other",
        ]),
        ContentCategory(id: "fitness_health", subcategories: [
            "workouts", "strength_training", "running", "yoga_pilates", "weight_loss",
            "nutrition", "mental_health", "sleep_recovery", "rehab", "supplements",
            "fitness_health_other",
        ]),
        ContentCategory(id: "music", subcategories: [
            "pop", "rock_metal", "hip_hop_rap", "electronic_dance", "jazz_blues", "classical",
            "country_folk", "latin", "kpop_jpop", "indie", "live_performance",
            "instrument_playing", "music_production", "lyrics_covers", "music_other",
        ]),
        ContentCategory(id: "gaming", subcategories: [
            "mobile_games", "pc_games", "console_games", "streaming", "speedruns",
            "game_reviews", "retro_games", "tabletop_rpg", "gamedev", "gaming_news",
            "gaming_other",
        ]),
        ContentCategory(id: "film_tv", subcategories: [
            "movies", "tv_series", "anime", "documentaries", "trailers", "reviews_recaps",
            "celebrities", "behind_the_scenes", "film_tv_other",
        ]),
        ContentCategory(id: "comedy_humor", subcategories: [
            "standup", "sketches", "memes", "pranks", "parody_satire", "funny_animals",
            "fails", "dark_humor", "comedy_humor_other",
        ]),
        ContentCategory(id: "food_drink", subcategories: [
            "recipes", "baking_desserts", "street_food", "restaurant_reviews",
            "vegan_vegetarian", "meal_prep", "coffee_tea", "cocktails_bar",
            "food_challenges", "food_drink_other",
        ]),
        ContentCategory(id: "travel", subcategories: [
            "destinations", "city_guides", "budget_travel", "luxury_travel",
            "hiking_camping", "road_trips", "aviation", "hotels", "travel_tips",
            "travel_other",
        ]),
        ContentCategory(id: "fashion_beauty", subcategories: [
            "outfits_style", "streetwear", "luxury_brands", "makeup", "skincare",
            "haircare", "nails", "vintage_thrift", "fashion_shows", "fashion_beauty_other",
        ]),
        ContentCategory(id: "technology", subcategories: [
            "smartphones", "computers_hardware", "software_apps", "ai_ml", "gadget_reviews",
            "cybersecurity", "space", "robotics", "programming", "tech_news",
            "technology_other",
        ]),
        ContentCategory(id: "science_education", subcategories: [
            "physics", "biology", "chemistry", "mathematics", "astronomy", "medicine",
            "psychology", "history", "geography", "languages", "study_tips",
            "science_education_other",
        ]),
        ContentCategory(id: "business_finance", subcategories: [
            "entrepreneurship", "startups", "marketing", "careers_jobs", "personal_finance",
            "investing", "crypto_web3", "real_estate", "economics", "management",
            "business_finance_other",
        ]),
        ContentCategory(id: "news_politics", subcategories: [
            "world_news", "local_news", "politics", "elections", "war_conflicts",
            "crime_courts", "protests", "laws", "journalism", "news_politics_other",
        ]),
        ContentCategory(id: "animals_pets", subcategories: [
            "dogs", "cats", "birds", "aquarium", "exotic_reptiles", "farm_animals",
            "wildlife", "pet_care", "training", "animals_pets_other",
        ]),
        ContentCategory(id: "art_design", subcategories: [
            "drawing_painting", "digital_art", "photography", "graphic_design",
            "animation_3d", "sculpture_ceramics", "tattoo", "architecture", "ui_ux",
            "art_design_other",
        ]),
        ContentCategory(id: "diy_crafts", subcategories: [
            "home_repair", "woodworking", "sewing_knitting", "gardening", "pottery",
            "upcycling", "electronics_diy", "paper_scrapbooking", "diy_crafts_other",
        ]),
        ContentCategory(id: "auto_moto", subcategories: [
            "cars", "motorcycles", "trucks_commercial", "ev_hybrids", "car_reviews",
            "tuning", "amateur_racing", "maintenance", "auto_moto_other",
        ]),
        ContentCategory(id: "lifestyle", subcategories: [
            "vlogs", "home_decor", "minimalism", "productivity", "self_improvement",
            "routines", "frugal_living", "cleaning_organization", "lifestyle_other",
        ]),
        ContentCategory(id: "relationships_family", subcategories: [
            "dating", "marriage", "parenting", "pregnancy_babies", "friendship",
            "breakups", "family_life", "relationship_advice", "relationships_family_other",
        ]),
        ContentCategory(id: "dance_performance", subcategories: [
            "choreography", "street_dance", "ballroom_latin", "ballet", "gymnastics_cheer",
            "theater", "circus_acrobatics", "dance_performance_other",
        ]),
        ContentCategory(id: "books_writing", subcategories: [
            "fiction", "nonfiction", "poetry", "book_reviews", "writing_craft",
            "comics_manga", "fanfiction", "quotes", "books_writing_other",
        ]),
        ContentCategory(id: "nature_environment", subcategories: [
            "landscapes", "weather_storms", "oceans_beaches", "mountains", "forests",
            "climate_conservation", "disasters", "nature_outdoors", "nature_environment_other",
        ]),
        ContentCategory(id: "spirituality_beliefs", subcategories: [
            "christianity", "islam", "judaism", "buddhism", "hinduism", "astrology_tarot",
            "meditation", "philosophy_ethics", "spirituality_beliefs_other",
        ]),
        ContentCategory(id: "social_causes", subcategories: [
            "charity", "volunteering", "human_rights", "lgbt", "gender_equality",
            "inclusion", "animal_rights", "eco_activism", "social_causes_other",
        ]),
        ContentCategory(id: "events_holidays", subcategories: [
            "birthdays", "weddings", "graduations", "festivals_concerts", "new_year",
            "halloween", "religious_holidays", "national_holidays", "events_holidays_other",
        ]),
        ContentCategory(id: "shopping_reviews", subcategories: [
            "hauls", "unboxing", "product_reviews", "deals", "dupes_comparisons", "resale",
            "shopping_reviews_other",
        ]),
        ContentCategory(id: "paranormal_mystery", subcategories: [
            "ufo", "ghosts", "cryptids", "conspiracy", "unsolved_mysteries",
            "paranormal_mystery_other",
        ]),
        ContentCategory(id: "community_meta", subcategories: [
            "introductions", "community_question", "polls", "platform_feedback",
            "announcements", "giveaways", "community_meta_other",
        ]),
        ContentCategory(id: "other", subcategories: ["other_general"]),
    ]

    static func category(id: String) -> ContentCategory? {
        all.first { $0.id == id }
    }
}
