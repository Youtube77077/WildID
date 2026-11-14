# BirdNET V2.4 evaluation on real recordings

Run 2026-11-14 · 160 research-grade iNaturalist recordings of 40 bird species recorded within 50 km of (52.46, 5.03).

| Metric | Value |
|---|---|
| top1 | 78.8% |
| top5 | 93.1% |
| top1_with_location_filter | 81.2% |
| top5_with_location_filter | 94.4% |
| detected_at_0.5 | 85.0% |
| detected_at_0.3 | 86.9% |
| mean_false_species_at_0.5 | 0.69 |
| mean_false_species_at_0.5_filtered | 0.39 |
| faint_wind_top1_filtered | 22.5% |
| faint_wind_top5_filtered | 33.8% |

Scores are the maximum over 3 s windows (1 s hop) of the first 60 s, as in the app. `faint_wind` is a stress test: each recording is turned 30 dB quieter (peak −30 dBFS) and mixed with strong synthetic wind and hiss. Recordings may contain other species, so 'other species' include real background animals, not only mistakes.

## Sensitivity settings (app rule: ≥ 2 windows above threshold, or one ≥ max(0.7, t+0.2); location filter on)

| Condition | Threshold | True species added | Other species added per recording |
|---|---|---|---|
| clean | 0.08 Maximum | 88.1% | 1.14 |
| clean | 0.15 Sensitive (default) | 86.2% | 0.66 |
| clean | 0.3 Balanced | 83.8% | 0.41 |
| clean | 0.5 Conservative | 82.5% | 0.31 |
| faint_wind | 0.08 Maximum | 20.0% | 0.23 |
| faint_wind | 0.15 Sensitive (default) | 15.6% | 0.12 |
| faint_wind | 0.3 Balanced | 12.5% | 0.06 |
| faint_wind | 0.5 Conservative | 9.4% | 0.04 |

## Per recording

| Species | Rank | Rank (filtered) | p(true) | Faint+wind p | Faint+wind rank | Top-1 | License |
|---|---|---|---|---|---|---|---|
| *Phylloscopus collybita* | 1 | 1 | 0.91 | 0.00 | 32 | Common Chiffchaff | cc-by-nc |
| *Phylloscopus collybita* | 3 | 681 | 0.08 | 0.00 | 681 | Scaly-breasted Munia | cc-by-nc |
| *Phylloscopus collybita* | 1 | 1 | 0.94 | 0.00 | 32 | Common Chiffchaff | cc-by-nc |
| *Phylloscopus collybita* | 1 | 1 | 0.99 | 0.00 | 21 | Common Chiffchaff | cc-by-nc |
| *Parus major* | 61 | 20 | 0.03 | 0.00 | 28 | Spotted Crake | cc-by-nc |
| *Parus major* | 1 | 1 | 1.00 | 0.89 | 1 | Great Tit | cc-by-nc |
| *Parus major* | 1 | 1 | 0.85 | 0.05 | 6 | Great Tit | cc-by-nc |
| *Parus major* | 1 | 1 | 0.88 | 0.00 | 87 | Great Tit | cc-by-nc |
| *Turdus merula* | 1 | 1 | 0.73 | 0.05 | 1 | Eurasian Blackbird | cc-by |
| *Turdus merula* | 1 | 1 | 0.26 | 0.00 | 8 | Eurasian Blackbird | cc-by-nc |
| *Turdus merula* | 2 | 2 | 1.00 | 0.53 | 1 | Collared Flycatcher | cc-by-nc |
| *Turdus merula* | 1 | 1 | 0.94 | 0.00 | 10 | Eurasian Blackbird | cc-by |
| *Psittacula krameri* | 1 | 1 | 1.00 | 0.17 | 1 | Rose-ringed Parakeet | cc0 |
| *Psittacula krameri* | 1 | 1 | 0.99 | 0.00 | 139 | Rose-ringed Parakeet | cc-by-nc |
| *Psittacula krameri* | 1 | 1 | 0.99 | 0.03 | 2 | Rose-ringed Parakeet | cc-by-nc |
| *Psittacula krameri* | 1 | 1 | 0.93 | 0.00 | 117 | Rose-ringed Parakeet | cc0 |
| *Erithacus rubecula* | 1 | 1 | 1.00 | 0.02 | 4 | European Robin | cc-by-nc |
| *Erithacus rubecula* | 1 | 1 | 0.99 | 0.04 | 2 | European Robin | cc-by |
| *Erithacus rubecula* | 1 | 1 | 1.00 | 0.08 | 2 | European Robin | cc-by |
| *Erithacus rubecula* | 1 | 1 | 0.98 | 0.04 | 6 | European Robin | cc-by-nc |
| *Acrocephalus scirpaceus* | 25 | 8 | 0.01 | 0.03 | 8 | Great Reed Warbler | cc-by-nc |
| *Acrocephalus scirpaceus* | 27 | 4314 | 0.03 | 0.00 | 4314 | Clamorous Reed Warbler | cc-by-nc |
| *Acrocephalus scirpaceus* | 1 | 1 | 0.95 | 0.00 | 60 | Eurasian Reed Warbler | cc-by-nc |
| *Acrocephalus scirpaceus* | 2 | 2 | 0.99 | 0.00 | 246 | Eurasian Penduline-Tit | cc-by-nc |
| *Luscinia megarhynchos* | 1 | 1 | 1.00 | 0.47 | 4 | Common Nightingale | cc-by-nc |
| *Luscinia megarhynchos* | 1 | 1 | 0.99 | 0.01 | 1 | Common Nightingale | cc-by |
| *Luscinia megarhynchos* | 1 | 1 | 0.98 | 0.00 | 89 | Common Nightingale | cc-by-nc |
| *Luscinia megarhynchos* | 1 | 1 | 0.98 | 0.61 | 1 | Common Nightingale | cc-by-nc |
| *Turdus philomelos* | 19 | 7 | 0.06 | 0.00 | 25 | European Goldfinch | cc-by |
| *Turdus philomelos* | 1 | 1 | 0.95 | 0.00 | 32 | Song Thrush | cc-by-nc |
| *Turdus philomelos* | 3 | 2 | 0.42 | 0.01 | 7 | Yellow-throated Vireo | cc-by-nc |
| *Turdus philomelos* | 1 | 1 | 0.92 | 0.03 | 3 | Song Thrush | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.99 | 0.00 | 132 | Common Cuckoo | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.96 | 0.00 | 274 | Common Cuckoo | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.94 | 0.00 | 97 | Common Cuckoo | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.98 | 0.00 | 126 | Common Cuckoo | cc-by |
| *Cettia cetti* | 2 | 2 | 0.98 | 0.00 | 118 | Common Chiffchaff | cc-by-nc |
| *Cettia cetti* | 1 | 1 | 0.79 | 0.00 | 74 | Cetti's Warbler | cc-by-nc |
| *Cettia cetti* | 1 | 1 | 1.00 | 0.00 | 2 | Cetti's Warbler | cc-by-nc |
| *Cettia cetti* | 2 | 3357 | 0.37 | 0.00 | 3357 | Common Cuckoo | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 0.99 | 0.00 | 101 | Sedge Warbler | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 0.98 | 0.00 | 332 | Sedge Warbler | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 0.78 | 0.00 | 137 | Sedge Warbler | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 1.00 | 0.71 | 1 | Sedge Warbler | cc-by-nc |
| *Sylvia atricapilla* | 1 | 1 | 0.99 | 0.00 | 139 | Eurasian Blackcap | cc-by-nc |
| *Sylvia atricapilla* | 20 | 6 | 0.02 | 0.00 | 87 | Abert's Towhee | cc-by-nc |
| *Sylvia atricapilla* | 1 | 1 | 1.00 | 0.03 | 2 | Eurasian Blackcap | cc-by |
| *Sylvia atricapilla* | 2 | 2 | 0.17 | 0.01 | 6 | Common Wood-Pigeon | cc-by-nc |
| *Strix aluco* | 1 | 1 | 0.96 | 0.00 | 20 | Tawny Owl | cc-by-nc |
| *Strix aluco* | 1 | 1 | 1.00 | 0.02 | 3 | Tawny Owl | cc-by-nc |
| *Strix aluco* | 1 | 1 | 1.00 | 0.00 | 7 | Tawny Owl | cc-by-nc |
| *Strix aluco* | 1 | 1 | 0.99 | 0.11 | 1911 | Tawny Owl | cc-by |
| *Phylloscopus trochilus* | 1 | 1 | 0.99 | 0.50 | 2 | Willow Warbler | cc-by-nc |
| *Phylloscopus trochilus* | 1 | 1 | 0.97 | 0.60 | 1 | Willow Warbler | cc-by-nc |
| *Phylloscopus trochilus* | 1 | 1 | 0.84 | 0.44 | 1 | Willow Warbler | cc-by-nc |
| *Phylloscopus trochilus* | 1 | 1 | 1.00 | 0.36 | 1 | Willow Warbler | cc-by-nc |
| *Cyanistes caeruleus* | 122 | 36 | 0.01 | 0.00 | 33 | Eurasian Bullfinch | cc-by-nc |
| *Cyanistes caeruleus* | 1 | 1 | 0.89 | 0.00 | 101 | Eurasian Blue Tit | cc-by-nc |
| *Cyanistes caeruleus* | 1 | 1 | 0.62 | 0.03 | 5 | Eurasian Blue Tit | cc-by-nc |
| *Cyanistes caeruleus* | 1 | 1 | 0.99 | 0.00 | 131 | Eurasian Blue Tit | cc-by |
| *Fringilla coelebs* | 1 | 1 | 0.97 | 0.01 | 11 | Common Chaffinch | cc-by |
| *Fringilla coelebs* | 1 | 1 | 1.00 | 0.21 | 6 | Common Chaffinch | cc-by-nc |
| *Fringilla coelebs* | 1 | 1 | 0.99 | 0.13 | 1 | Common Chaffinch | cc-by-nc |
| *Fringilla coelebs* | 1 | 1 | 1.00 | 0.18 | 1 | Common Chaffinch | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 0.98 | 0.39 | 1 | Dunnock | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 1.00 | 0.92 | 1 | Dunnock | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 0.99 | 0.85 | 1 | Dunnock | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 0.97 | 0.05 | 1 | Dunnock | cc-by-nc |
| *Rallus aquaticus* | 3 | 1 | 0.62 | 0.00 | 135 | Sharp-shinned Hawk | cc-by-nc |
| *Rallus aquaticus* | 1 | 1 | 0.70 | 0.03 | 6 | Water Rail | cc-by |
| *Rallus aquaticus* | 1 | 1 | 1.00 | 0.00 | 48 | Water Rail | cc-by-nc |
| *Rallus aquaticus* | 1 | 1 | 1.00 | 0.83 | 1 | Water Rail | cc-by-nc |
| *Curruca curruca* | 1 | 1 | 1.00 | 0.24 | 1 | Lesser Whitethroat | cc-by-nc |
| *Curruca curruca* | 1 | 1 | 0.92 | 0.00 | 122 | Lesser Whitethroat | cc-by-nc |
| *Curruca curruca* | 3 | 2 | 0.06 | 0.00 | 133 | Eurasian Blackcap | cc-by-nc |
| *Curruca curruca* | 1 | 1 | 1.00 | 0.01 | 8 | Lesser Whitethroat | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.96 | 0.29 | 1 | Eurasian Coot | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.85 | 0.00 | 13 | Eurasian Coot | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.68 | 0.01 | 5 | Eurasian Coot | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.87 | 0.02 | 5 | Eurasian Coot | cc-by-nc |
| *Asio otus* | 1 | 1 | 1.00 | 0.99 | 1 | Long-eared Owl | cc-by-nc |
| *Asio otus* | 1 | 1 | 1.00 | 1.00 | 1 | Long-eared Owl | cc-by-nc |
| *Asio otus* | 1 | 1 | 1.00 | 0.98 | 1 | Long-eared Owl | cc-by |
| *Asio otus* | 11 | 5 | 0.00 | 0.00 | 15 | Crowned Lapwing | cc-by-nc |
| *Sylvia borin* | 1 | 1 | 1.00 | 0.04 | 1981 | Garden Warbler | cc-by-nc |
| *Sylvia borin* | 3 | 2 | 0.36 | 0.00 | 190 | Pine Grosbeak | cc-by-nc |
| *Sylvia borin* | 1 | 1 | 0.98 | 0.00 | 213 | Garden Warbler | cc-by-nc |
| *Sylvia borin* | 1 | 1 | 0.97 | 0.00 | 184 | Garden Warbler | cc-by |
| *Acrocephalus palustris* | 2 | 2 | 0.99 | 0.01 | 49 | European Bee-eater | cc-by-nc |
| *Acrocephalus palustris* | 1 | 1 | 0.74 | 0.00 | 179 | Marsh Warbler | cc-by-nc |
| *Acrocephalus palustris* | 1 | 1 | 0.99 | 0.00 | 112 | Marsh Warbler | cc-by-nc |
| *Acrocephalus palustris* | 1 | 1 | 0.87 | 0.00 | 120 | Marsh Warbler | cc0 |
| *Pica pica* | 1 | 1 | 0.96 | 0.00 | 58 | Eurasian Magpie | cc-by |
| *Pica pica* | 2 | 1 | 0.66 | 0.00 | 49 | Monk Parakeet | cc-by-nc |
| *Pica pica* | 1 | 1 | 1.00 | 0.00 | 70 | Eurasian Magpie | cc-by |
| *Pica pica* | 1 | 1 | 1.00 | 0.04 | 1 | Eurasian Magpie | cc-by-nc |
| *Carduelis carduelis* | 1 | 1 | 0.90 | 0.00 | 41 | European Goldfinch | cc-by |
| *Carduelis carduelis* | 1 | 1 | 1.00 | 0.00 | 36 | European Goldfinch | cc-by-nc |
| *Carduelis carduelis* | 1 | 1 | 0.99 | 0.98 | 1 | European Goldfinch | cc-by-nc |
| *Carduelis carduelis* | 4 | 2 | 0.16 | 0.00 | 32 | Rock Wren | cc-by-nc |
| *Locustella luscinioides* | 1 | 1 | 1.00 | 0.00 | 124 | Savi's Warbler | cc-by-nc |
| *Locustella luscinioides* | 1 | 1 | 1.00 | 0.98 | 1 | Savi's Warbler | cc-by |
| *Locustella luscinioides* | 2 | 2 | 1.00 | 0.00 | 142 | Eurasian Coot | cc-by-nc |
| *Locustella luscinioides* | 1 | 1 | 0.99 | 0.00 | 103 | Savi's Warbler | cc-by |
| *Lullula arborea* | 1 | 1 | 1.00 | 0.98 | 1 | Wood Lark | cc-by-nc |
| *Lullula arborea* | 1 | 1 | 1.00 | 0.11 | 2 | Wood Lark | cc-by-nc |
| *Lullula arborea* | 1 | 1 | 0.67 | 0.00 | 79 | Wood Lark | cc-by-nc |
| *Lullula arborea* | 1 | 1 | 0.96 | 0.00 | 96 | Wood Lark | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 1.00 | 0.00 | 144 | Short-toed Treecreeper | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 0.98 | 0.26 | 1 | Short-toed Treecreeper | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 0.94 | 0.05 | 5 | Short-toed Treecreeper | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 0.94 | 0.95 | 1 | Short-toed Treecreeper | cc-by-nc |
| *Sitta europaea* | 1 | 1 | 0.99 | 0.00 | 68 | Eurasian Nuthatch | cc-by-nc |
| *Sitta europaea* | 1 | 1 | 1.00 | 0.00 | 73 | Eurasian Nuthatch | cc-by-nc-sa |
| *Sitta europaea* | 1 | 1 | 1.00 | 0.00 | 111 | Eurasian Nuthatch | cc-by |
| *Sitta europaea* | 5 | 1 | 0.03 | 0.00 | 62 | Rusty Blackbird | cc-by |
| *Dendrocopos major* | 1 | 1 | 0.96 | 0.00 | 21 | Great Spotted Woodpecker | cc-by-nc |
| *Dendrocopos major* | 1 | 1 | 1.00 | 0.00 | 22 | Great Spotted Woodpecker | cc-by-nc |
| *Dendrocopos major* | 1 | 1 | 0.99 | 0.00 | 22 | Great Spotted Woodpecker | cc-by-nc |
| *Dendrocopos major* | 3 | 2 | 0.10 | 0.20 | 1 | Eurasian Three-toed Woodpecker | cc-by-nc |
| *Caprimulgus europaeus* | 1 | 1 | 1.00 | 0.00 | 107 | Eurasian Nightjar | cc-by-nc |
| *Caprimulgus europaeus* | 1 | 1 | 0.95 | 0.00 | 3685 | Eurasian Nightjar | cc-by-nc |
| *Caprimulgus europaeus* | 1 | 1 | 0.99 | 0.00 | 3699 | Eurasian Nightjar | cc-by-nc |
| *Caprimulgus europaeus* | 1 | 1 | 1.00 | 1.00 | 1 | Eurasian Nightjar | cc-by-nc |
| *Garrulus glandarius* | 8 | 5 | 0.07 | 0.00 | 43 | European Greenfinch | cc-by-nc |
| *Garrulus glandarius* | 3 | 2 | 0.11 | 0.00 | 61 | Common Buzzard | cc-by-nc |
| *Garrulus glandarius* | 28 | 5 | 0.03 | 0.00 | 66 | Brown Jay | cc-by-nc |
| *Garrulus glandarius* | 1 | 1 | 0.99 | 0.00 | 63 | Eurasian Jay | cc-by-nc |
| *Anthus trivialis* | 1 | 1 | 0.99 | 0.00 | 18 | Tree Pipit | cc-by-nc |
| *Anthus trivialis* | 1 | 1 | 0.99 | 0.00 | 22 | Tree Pipit | cc-by |
| *Anthus trivialis* | 2 | 1 | 0.24 | 0.00 | 23 | Eastern Yellow Wagtail | cc-by |
| *Anthus trivialis* | 1 | 1 | 0.94 | 0.01 | 2 | Tree Pipit | cc-by-nc |
| *Dryocopus martius* | 1 | 1 | 1.00 | 0.00 | 116 | Black Woodpecker | cc-by-nc |
| *Dryocopus martius* | 1 | 1 | 1.00 | 0.04 | 5906 | Black Woodpecker | cc-by |
| *Dryocopus martius* | 1 | 1 | 1.00 | 0.23 | 1 | Black Woodpecker | cc-by-nc |
| *Dryocopus martius* | 1 | 1 | 0.98 | 0.00 | 117 | Black Woodpecker | cc-by-nc |
| *Psittacula eupatria* | 1 | 1 | 1.00 | 0.00 | 2888 | Alexandrine Parakeet | cc-by-nc |
| *Psittacula eupatria* | 1 | 1 | 0.93 | 0.00 | 2891 | Alexandrine Parakeet | cc-by-nc |
| *Psittacula eupatria* | 1 | 1 | 1.00 | 0.00 | 2885 | Alexandrine Parakeet | cc-by-nc |
| *Psittacula eupatria* | 1 | 1 | 0.96 | 0.01 | 2884 | Alexandrine Parakeet | cc-by-nc |
| *Haematopus ostralegus* | 1 | 1 | 1.00 | 0.19 | 1 | Eurasian Oystercatcher | cc0 |
| *Haematopus ostralegus* | 1 | 1 | 0.97 | 0.25 | 1 | Eurasian Oystercatcher | cc-by |
| *Haematopus ostralegus* | 1 | 1 | 0.97 | 0.00 | 5229 | Eurasian Oystercatcher | cc-by |
| *Haematopus ostralegus* | 1 | 1 | 0.99 | 0.00 | 36 | Eurasian Oystercatcher | cc-by-nc |
| *Alauda arvensis* | 12 | 6 | 0.06 | 0.00 | 33 | Horned Lark | cc-by-nc |
| *Alauda arvensis* | 1 | 1 | 0.88 | 0.00 | 2 | Eurasian Skylark | cc-by-nc-sa |
| *Alauda arvensis* | 1 | 1 | 0.80 | 0.41 | 1 | Eurasian Skylark | cc-by-nc |
| *Alauda arvensis* | 1 | 1 | 1.00 | 0.00 | 18 | Eurasian Skylark | cc-by |
| *Hippolais icterina* | 6 | 3 | 0.18 | 0.00 | 124 | Eurasian Blackcap | cc-by-nc |
| *Hippolais icterina* | 1 | 1 | 1.00 | 0.00 | 52 | Icterine Warbler | cc-by-nc |
| *Hippolais icterina* | 1 | 1 | 0.83 | 0.00 | 146 | Icterine Warbler | cc-by-nc |
| *Hippolais icterina* | 1 | 1 | 1.00 | 0.00 | 117 | Icterine Warbler | cc-by-nc |
| *Locustella naevia* | 1 | 1 | 0.99 | 0.00 | 284 | Common Grasshopper-Warbler | cc-by-nc |
| *Locustella naevia* | 2 | 2 | 0.96 | 0.90 | 1 | Corn Crake | cc-by-nc |
| *Locustella naevia* | 1 | 1 | 1.00 | 0.00 | 5425 | Common Grasshopper-Warbler | cc-by-nc |
| *Locustella naevia* | 2 | 2 | 0.95 | 0.00 | 5431 | River Warbler | cc-by-nc |
| *Corvus corone* | 2 | 2 | 0.81 | 0.00 | 10 | Hooded Crow | cc-by-nc |
| *Corvus corone* | 4 | 2 | 0.29 | 0.00 | 26 | European Goldfinch | cc-by |
| *Corvus corone* | 2 | 2 | 0.65 | 0.41 | 1 | Hooded Crow | cc-by-nc |
| *Corvus corone* | 1 | 1 | 0.90 | 0.63 | 2 | Carrion Crow | cc-by-nc |
