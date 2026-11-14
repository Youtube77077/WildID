# BirdNET V2.4 evaluation on real recordings

Run 2026-11-14 · 160 research-grade iNaturalist recordings of 40 bird species recorded within 50 km of (52.46, 5.03).

| Metric | Value |
|---|---|
| top1 | 79.4% |
| top5 | 91.9% |
| top1_with_location_filter | 80.6% |
| top5_with_location_filter | 94.4% |
| detected_at_0.5 | 83.8% |
| detected_at_0.3 | 86.9% |
| mean_false_species_at_0.5 | 0.62 |
| mean_false_species_at_0.5_filtered | 0.37 |

Scores are the maximum over 3 s windows (1.5 s hop) of the first 60 s, as in the app. Recordings may contain other species, so 'false' detections include real background birds.

## Per recording

| Species | Rank | Rank (filtered) | p(true) | Top-1 | License |
|---|---|---|---|---|---|
| *Phylloscopus collybita* | 1 | 1 | 0.82 | Common Chiffchaff | cc-by-nc |
| *Phylloscopus collybita* | 3 | 4542 | 0.08 | Scaly-breasted Munia | cc-by-nc |
| *Phylloscopus collybita* | 1 | 1 | 0.94 | Common Chiffchaff | cc-by-nc |
| *Phylloscopus collybita* | 2 | 2 | 0.41 | Rook | cc-by |
| *Parus major* | 49 | 19 | 0.03 | Spotted Crake | cc-by-nc |
| *Parus major* | 1 | 1 | 0.88 | Great Tit | cc-by-nc |
| *Parus major* | 1 | 1 | 0.86 | Great Tit | cc-by-nc |
| *Parus major* | 1 | 1 | 1.00 | Great Tit | cc-by-nc |
| *Turdus merula* | 1 | 1 | 0.73 | Eurasian Blackbird | cc-by |
| *Turdus merula* | 1 | 1 | 0.26 | Eurasian Blackbird | cc-by-nc |
| *Turdus merula* | 2 | 2 | 1.00 | Collared Flycatcher | cc-by-nc |
| *Turdus merula* | 1 | 1 | 0.87 | Eurasian Blackbird | cc-by-nc |
| *Psittacula krameri* | 1 | 1 | 1.00 | Rose-ringed Parakeet | cc0 |
| *Psittacula krameri* | 1 | 1 | 0.98 | Rose-ringed Parakeet | cc-by-nc |
| *Psittacula krameri* | 1 | 1 | 0.99 | Rose-ringed Parakeet | cc-by-nc |
| *Psittacula krameri* | 1 | 1 | 0.93 | Rose-ringed Parakeet | cc0 |
| *Erithacus rubecula* | 1 | 1 | 1.00 | European Robin | cc-by-nc |
| *Erithacus rubecula* | 1 | 1 | 1.00 | European Robin | cc-by |
| *Erithacus rubecula* | 1 | 1 | 0.96 | European Robin | cc-by-nc |
| *Erithacus rubecula* | 1 | 1 | 0.99 | European Robin | cc-by |
| *Acrocephalus scirpaceus* | 74 | 16 | 0.00 | Great Reed Warbler | cc-by-nc |
| *Acrocephalus scirpaceus* | 23 | 4927 | 0.03 | Marsh Warbler | cc-by-nc |
| *Acrocephalus scirpaceus* | 1 | 1 | 0.91 | Eurasian Reed Warbler | cc-by-nc |
| *Acrocephalus scirpaceus* | 2 | 2 | 0.96 | Eurasian Penduline-Tit | cc-by-nc |
| *Luscinia megarhynchos* | 1 | 1 | 1.00 | Common Nightingale | cc-by-nc |
| *Luscinia megarhynchos* | 1 | 1 | 0.97 | Common Nightingale | cc-by-nc |
| *Luscinia megarhynchos* | 1 | 1 | 0.98 | Common Nightingale | cc-by-nc |
| *Luscinia megarhynchos* | 1 | 1 | 0.99 | Common Nightingale | cc-by |
| *Turdus philomelos* | 1 | 1 | 0.95 | Song Thrush | cc-by-nc |
| *Turdus philomelos* | 15 | 3 | 0.08 | Squirrel Cuckoo | cc-by |
| *Turdus philomelos* | 6 | 3 | 0.22 | Yellow-throated Vireo | cc-by-nc |
| *Turdus philomelos* | 1 | 1 | 0.90 | Song Thrush | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.99 | Common Cuckoo | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.93 | Common Cuckoo | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.81 | Common Cuckoo | cc-by-nc |
| *Cuculus canorus* | 1 | 1 | 0.98 | Common Cuckoo | cc-by |
| *Cettia cetti* | 2 | 2 | 0.95 | Common Chiffchaff | cc-by-nc |
| *Cettia cetti* | 1 | 1 | 0.52 | Cetti's Warbler | cc-by-nc |
| *Cettia cetti* | 1 | 1 | 1.00 | Cetti's Warbler | cc-by-nc |
| *Cettia cetti* | 2 | 1146 | 0.14 | Common Cuckoo | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 0.99 | Sedge Warbler | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 0.98 | Sedge Warbler | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 0.86 | Sedge Warbler | cc-by-nc |
| *Acrocephalus schoenobaenus* | 1 | 1 | 1.00 | Sedge Warbler | cc-by-nc |
| *Sylvia atricapilla* | 1 | 1 | 0.99 | Eurasian Blackcap | cc-by-nc |
| *Sylvia atricapilla* | 1 | 1 | 0.39 | Eurasian Blackcap | cc-by-nc-sa |
| *Sylvia atricapilla* | 1 | 1 | 0.97 | Eurasian Blackcap | cc-by |
| *Sylvia atricapilla* | 2 | 2 | 0.16 | Common Wood-Pigeon | cc-by-nc |
| *Strix aluco* | 1 | 1 | 0.99 | Tawny Owl | cc-by-nc |
| *Strix aluco* | 1 | 1 | 0.99 | Tawny Owl | cc-by-nc |
| *Strix aluco* | 1 | 1 | 1.00 | Tawny Owl | cc-by-nc |
| *Strix aluco* | 1 | 1 | 0.99 | Tawny Owl | cc-by |
| *Phylloscopus trochilus* | 1 | 1 | 0.96 | Willow Warbler | cc-by-nc |
| *Phylloscopus trochilus* | 1 | 1 | 0.97 | Willow Warbler | cc-by-nc |
| *Phylloscopus trochilus* | 1 | 1 | 0.35 | Willow Warbler | cc-by-nc |
| *Phylloscopus trochilus* | 1 | 1 | 1.00 | Willow Warbler | cc-by-nc |
| *Cyanistes caeruleus* | 105 | 29 | 0.01 | Eurasian Bullfinch | cc-by-nc |
| *Cyanistes caeruleus* | 1 | 1 | 0.84 | Eurasian Blue Tit | cc-by-nc |
| *Cyanistes caeruleus* | 2 | 2 | 0.62 | Common Chiffchaff | cc-by-nc |
| *Cyanistes caeruleus* | 1 | 1 | 0.98 | Eurasian Blue Tit | cc-by |
| *Fringilla coelebs* | 1 | 1 | 0.97 | Common Chaffinch | cc-by |
| *Fringilla coelebs* | 1 | 1 | 0.99 | Common Chaffinch | cc-by-nc |
| *Fringilla coelebs* | 1 | 1 | 1.00 | Common Chaffinch | cc-by-nc |
| *Fringilla coelebs* | 1 | 1 | 0.99 | Common Chaffinch | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 0.96 | Dunnock | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 1.00 | Dunnock | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 0.99 | Dunnock | cc-by-nc |
| *Prunella modularis* | 1 | 1 | 0.97 | Dunnock | cc-by-nc |
| *Rallus aquaticus* | 2 | 1 | 0.62 | Sharp-shinned Hawk | cc-by-nc |
| *Rallus aquaticus* | 1 | 1 | 0.96 | Water Rail | cc-by |
| *Rallus aquaticus* | 1 | 1 | 1.00 | Water Rail | cc-by-nc |
| *Rallus aquaticus* | 1 | 1 | 1.00 | Water Rail | cc-by-nc |
| *Curruca curruca* | 1 | 1 | 1.00 | Lesser Whitethroat | cc-by-nc |
| *Curruca curruca* | 1 | 1 | 0.92 | Lesser Whitethroat | cc-by-nc |
| *Curruca curruca* | 1 | 1 | 0.98 | Lesser Whitethroat | cc-by-nc |
| *Curruca curruca* | 5 | 2 | 0.04 | Eurasian Blackcap | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.93 | Eurasian Coot | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.85 | Eurasian Coot | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.68 | Eurasian Coot | cc-by-nc |
| *Fulica atra* | 1 | 1 | 0.94 | Eurasian Coot | cc-by-nc |
| *Asio otus* | 1 | 1 | 1.00 | Long-eared Owl | cc-by-nc |
| *Asio otus* | 1 | 1 | 1.00 | Long-eared Owl | cc-by |
| *Asio otus* | 1 | 1 | 1.00 | Long-eared Owl | cc-by-nc |
| *Asio otus* | 12 | 6 | 0.00 | Crowned Lapwing | cc-by-nc |
| *Sylvia borin* | 1 | 1 | 1.00 | Garden Warbler | cc-by-nc |
| *Sylvia borin* | 2 | 1 | 0.36 | White-eyed Vireo | cc-by-nc |
| *Sylvia borin* | 1 | 1 | 0.99 | Garden Warbler | cc-by-nc |
| *Sylvia borin* | 1 | 1 | 0.92 | Garden Warbler | cc-by |
| *Acrocephalus palustris* | 1 | 1 | 0.99 | Marsh Warbler | cc-by-nc |
| *Acrocephalus palustris* | 1 | 1 | 0.74 | Marsh Warbler | cc-by-nc |
| *Acrocephalus palustris* | 1 | 1 | 0.99 | Marsh Warbler | cc-by-nc |
| *Acrocephalus palustris* | 1 | 1 | 0.90 | Marsh Warbler | cc0 |
| *Pica pica* | 1 | 1 | 0.99 | Eurasian Magpie | cc-by |
| *Pica pica* | 1 | 1 | 0.69 | Eurasian Magpie | cc-by-nc |
| *Pica pica* | 1 | 1 | 0.99 | Eurasian Magpie | cc-by-nc |
| *Pica pica* | 1 | 1 | 1.00 | Eurasian Magpie | cc-by-nc |
| *Carduelis carduelis* | 1 | 1 | 0.90 | European Goldfinch | cc-by |
| *Carduelis carduelis* | 1 | 1 | 1.00 | European Goldfinch | cc-by-nc |
| *Carduelis carduelis* | 1 | 1 | 0.99 | European Goldfinch | cc-by-nc |
| *Carduelis carduelis* | 4 | 2 | 0.08 | Lapland Longspur | cc-by-nc |
| *Locustella luscinioides* | 1 | 1 | 1.00 | Savi's Warbler | cc-by-nc |
| *Locustella luscinioides* | 1 | 1 | 1.00 | Savi's Warbler | cc-by |
| *Locustella luscinioides* | 2 | 2 | 1.00 | Eurasian Coot | cc-by-nc |
| *Locustella luscinioides* | 1 | 1 | 0.99 | Savi's Warbler | cc-by |
| *Lullula arborea* | 1 | 1 | 1.00 | Wood Lark | cc-by-nc |
| *Lullula arborea* | 1 | 1 | 1.00 | Wood Lark | cc-by-nc |
| *Lullula arborea* | 1 | 1 | 0.84 | Wood Lark | cc-by-nc |
| *Lullula arborea* | 1 | 1 | 0.92 | Wood Lark | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 1.00 | Short-toed Treecreeper | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 0.98 | Short-toed Treecreeper | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 0.94 | Short-toed Treecreeper | cc-by-nc |
| *Certhia brachydactyla* | 1 | 1 | 0.94 | Short-toed Treecreeper | cc-by-nc |
| *Sitta europaea* | 1 | 1 | 0.99 | Eurasian Nuthatch | cc-by-nc |
| *Sitta europaea* | 1 | 1 | 1.00 | Eurasian Nuthatch | cc-by-nc-sa |
| *Sitta europaea* | 1 | 1 | 1.00 | Eurasian Nuthatch | cc-by |
| *Sitta europaea* | 6 | 3 | 0.03 | Rusty Blackbird | cc-by |
| *Dendrocopos major* | 1 | 1 | 0.97 | Great Spotted Woodpecker | cc-by-nc |
| *Dendrocopos major* | 1 | 1 | 1.00 | Great Spotted Woodpecker | cc-by-nc |
| *Dendrocopos major* | 1 | 1 | 1.00 | Great Spotted Woodpecker | cc-by-nc |
| *Dendrocopos major* | 2 | 2 | 0.83 | Common Wood-Pigeon | cc-by |
| *Caprimulgus europaeus* | 1 | 1 | 1.00 | Eurasian Nightjar | cc-by-nc |
| *Caprimulgus europaeus* | 1 | 1 | 0.97 | Eurasian Nightjar | cc-by-nc |
| *Caprimulgus europaeus* | 1 | 1 | 0.99 | Eurasian Nightjar | cc-by-nc |
| *Caprimulgus europaeus* | 1 | 1 | 1.00 | Eurasian Nightjar | cc-by-nc |
| *Garrulus glandarius* | 9 | 4 | 0.05 | European Greenfinch | cc-by-nc |
| *Garrulus glandarius* | 6 | 2 | 0.05 | Common Buzzard | cc-by-nc |
| *Garrulus glandarius* | 22 | 4 | 0.03 | Brown Jay | cc-by-nc |
| *Garrulus glandarius* | 1 | 1 | 0.99 | Eurasian Jay | cc-by-nc |
| *Anthus trivialis* | 1 | 1 | 0.99 | Tree Pipit | cc-by-nc |
| *Anthus trivialis* | 1 | 1 | 0.99 | Tree Pipit | cc-by |
| *Anthus trivialis* | 3 | 2 | 0.20 | Eastern Yellow Wagtail | cc-by |
| *Anthus trivialis* | 1 | 1 | 0.94 | Tree Pipit | cc-by-nc |
| *Dryocopus martius* | 1 | 1 | 1.00 | Black Woodpecker | cc-by-nc |
| *Dryocopus martius* | 1 | 1 | 1.00 | Black Woodpecker | cc-by |
| *Dryocopus martius* | 1 | 1 | 1.00 | Black Woodpecker | cc-by-nc |
| *Dryocopus martius* | 1 | 1 | 0.98 | Black Woodpecker | cc-by |
| *Psittacula eupatria* | 1 | 1 | 1.00 | Alexandrine Parakeet | cc-by-nc |
| *Psittacula eupatria* | 1 | 1 | 0.95 | Alexandrine Parakeet | cc-by-nc |
| *Psittacula eupatria* | 1 | 1 | 1.00 | Alexandrine Parakeet | cc-by-nc |
| *Psittacula eupatria* | 1 | 1 | 0.96 | Alexandrine Parakeet | cc-by-nc |
| *Haematopus ostralegus* | 1 | 1 | 1.00 | Eurasian Oystercatcher | cc0 |
| *Haematopus ostralegus* | 1 | 1 | 0.97 | Eurasian Oystercatcher | cc-by |
| *Haematopus ostralegus* | 1 | 1 | 0.97 | Eurasian Oystercatcher | cc-by |
| *Haematopus ostralegus* | 1 | 1 | 0.99 | Eurasian Oystercatcher | cc-by-nc |
| *Alauda arvensis* | 15 | 9 | 0.04 | Horned Lark | cc-by-nc |
| *Alauda arvensis* | 1 | 1 | 0.88 | Eurasian Skylark | cc-by-nc-sa |
| *Alauda arvensis* | 1 | 1 | 1.00 | Eurasian Skylark | cc-by |
| *Alauda arvensis* | 1 | 1 | 0.80 | Eurasian Skylark | cc-by-nc |
| *Hippolais icterina* | 6 | 3 | 0.12 | Common Waxbill | cc-by-nc |
| *Hippolais icterina* | 1 | 1 | 1.00 | Icterine Warbler | cc-by-nc |
| *Hippolais icterina* | 1 | 1 | 1.00 | Icterine Warbler | cc-by-nc |
| *Hippolais icterina* | 1 | 1 | 0.77 | Icterine Warbler | cc-by-nc |
| *Locustella naevia* | 1 | 1 | 0.99 | Common Grasshopper-Warbler | cc-by-nc |
| *Locustella naevia* | 2 | 2 | 0.94 | Corn Crake | cc-by-nc |
| *Locustella naevia* | 1 | 1 | 1.00 | Common Grasshopper-Warbler | cc-by-nc |
| *Locustella naevia* | 5 | 3248 | 0.46 | River Warbler | cc-by-nc |
| *Corvus corone* | 2 | 2 | 0.72 | Hooded Crow | cc-by-nc |
| *Corvus corone* | 2 | 2 | 0.29 | European Goldfinch | cc-by |
| *Corvus corone* | 2 | 2 | 0.65 | Hooded Crow | cc-by-nc |
| *Corvus corone* | 1 | 1 | 0.90 | Carrion Crow | cc-by-nc |
